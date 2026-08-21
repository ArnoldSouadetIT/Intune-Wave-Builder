# Shared helpers for Intune Wave Builder scripts. Dot-source this file; do not run directly.

$script:WaveRegistryPath = Join-Path $env:LOCALAPPDATA 'IntuneWaveBuilder\clients.json'
$script:GraphAppId = '00000003-0000-0000-c000-000000000000'

function Assert-WaveGraphAuthModule {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Host "Installation du module Microsoft.Graph.Authentication (une seule fois)..." -ForegroundColor Yellow
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
}

function Get-WaveClientRegistry {
    if (-not (Test-Path $script:WaveRegistryPath)) { return @() }
    $raw = Get-Content $script:WaveRegistryPath -Raw | ConvertFrom-Json
    if ($null -eq $raw) { return @() }
    return @($raw)
}

function Get-WaveClientEntry {
    param([Parameter(Mandatory)][string]$ClientName)
    $entry = Get-WaveClientRegistry | Where-Object { $_.ClientName -eq $ClientName }
    if (-not $entry) {
        throw "Aucune entree trouvee pour le client '$ClientName' dans $script:WaveRegistryPath. Lance d'abord Bootstrap-TenantApp.ps1 -ClientName '$ClientName'."
    }
    return $entry
}

function Save-WaveClientEntry {
    param(
        [Parameter(Mandatory)][string]$ClientName,
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$CertThumbprint
    )
    $registryDir = Split-Path $script:WaveRegistryPath -Parent
    if (-not (Test-Path $registryDir)) { New-Item -ItemType Directory -Path $registryDir -Force | Out-Null }

    $entries = @(Get-WaveClientRegistry | Where-Object { $_.ClientName -ne $ClientName })
    $entries += [pscustomobject]@{
        ClientName     = $ClientName
        TenantId       = $TenantId
        ClientId       = $ClientId
        CertThumbprint = $CertThumbprint
        CreatedUtc     = (Get-Date).ToUniversalTime().ToString('o')
    }
    $entries | ConvertTo-Json -Depth 5 | Set-Content -Path $script:WaveRegistryPath -Encoding UTF8
}

function Remove-WaveClientEntry {
    param([Parameter(Mandatory)][string]$ClientName)
    $entries = @(Get-WaveClientRegistry | Where-Object { $_.ClientName -ne $ClientName })
    $entries | ConvertTo-Json -Depth 5 | Set-Content -Path $script:WaveRegistryPath -Encoding UTF8
}

function Connect-WaveGraphInteractive {
    param([Parameter(Mandatory)][string[]]$Scopes)
    Assert-WaveGraphAuthModule
    Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
}

function Connect-WaveGraphApp {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$CertThumbprint
    )
    Assert-WaveGraphAuthModule
    Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertThumbprint -NoWelcome -ErrorAction Stop
}

function Resolve-WaveTargetType {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    switch ($Raw.Trim().ToLowerInvariant()) {
        { $_ -in @('device', 'devices', 'd') } { return 'Device' }
        { $_ -in @('user', 'users', 'u') } { return 'User' }
        default { return $null }
    }
}

function Resolve-WavePlatform {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    switch ($Raw.Trim().ToLowerInvariant()) {
        { $_ -in @('windows', 'win', 'w') } { return 'Windows' }
        { $_ -in @('android', 'a') } { return 'Android' }
        { $_ -in @('ios', 'i') } { return 'iOS' }
        { $_ -in @('linux', 'l') } { return 'Linux' }
        { $_ -in @('macos', 'mac', 'osx', 'm') } { return 'macOS' }
        { $_ -in @('all', 'tous', 'toutes', 't') } { return 'All' }
        default { return $null }
    }
}

function Get-WaveOrganizationInfo {
    param(
        [Parameter(Mandatory)][string]$ExpectedTenantId
    )
    $org = (Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id,displayName,verifiedDomains').value | Select-Object -First 1
    if (-not $org) { throw "Impossible de recuperer les informations d'organisation (endpoint /organization) pour verifier le tenant." }

    $primaryDomain = ($org.verifiedDomains | Where-Object { $_.isDefault }).name
    if (-not $primaryDomain) { $primaryDomain = ($org.verifiedDomains | Select-Object -First 1).name }

    # Matches=$false is returned rather than thrown here so callers can display
    # the actually-connected tenant's Name/Domain BEFORE aborting - the whole
    # point of this check is to let the user recognize a wrong-tenant connection.
    return [pscustomobject]@{
        Id            = $org.id
        DisplayName   = $org.displayName
        PrimaryDomain = $primaryDomain
        Matches       = ($org.id -eq $ExpectedTenantId)
    }
}

function Confirm-WaveTenant {
    param(
        [Parameter(Mandatory)][string]$ExpectedTenantId
    )
    $info = Get-WaveOrganizationInfo -ExpectedTenantId $ExpectedTenantId

    Write-Host ""
    Write-Host "=====================================================" -ForegroundColor Yellow
    Write-Host " Tenant connecte :" -ForegroundColor Yellow
    Write-Host "   Nom          : $($info.DisplayName)" -ForegroundColor Yellow
    Write-Host "   Domaine      : $($info.PrimaryDomain)" -ForegroundColor Yellow
    Write-Host "   TenantId     : $($info.Id)" -ForegroundColor Yellow
    Write-Host "=====================================================" -ForegroundColor Yellow

    if (-not $info.Matches) {
        throw "Le TenantId retourne par /organization ($($info.Id)) ne correspond pas au TenantId fourni ($ExpectedTenantId). Abandon par securite."
    }

    $answer = Read-Host "Confirmer la creation des groupes dans CE tenant ? (O/N)"
    if ($answer -notmatch '^[oOyY]') {
        throw "Operation annulee par l'utilisateur (tenant non confirme)."
    }
}

function Invoke-WaveGraphPaged {
    param([Parameter(Mandatory)][string]$Uri)
    $results = [System.Collections.Generic.List[object]]::new()
    $nextUri = $Uri
    while ($nextUri) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextUri
        if ($response.value) { $results.AddRange(@($response.value)) }
        $nextUri = $response.'@odata.nextLink'
    }
    return $results
}

function Get-WaveGraphAppRoleIds {
    param([Parameter(Mandatory)][string[]]$PermissionNames)

    $graphSpUri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$script:GraphAppId'"
    $graphSp = (Invoke-MgGraphRequest -Method GET -Uri $graphSpUri).value | Select-Object -First 1
    if (-not $graphSp) { throw "Impossible de trouver le service principal Microsoft Graph dans ce tenant." }

    $resolved = foreach ($name in $PermissionNames) {
        $role = $graphSp.appRoles | Where-Object { $_.value -eq $name -and $_.allowedMemberTypes -contains 'Application' }
        if (-not $role) { throw "Permission applicative '$name' introuvable sur le service principal Graph. Verifie le nom exact." }
        [pscustomobject]@{ Name = $name; Id = $role.id }
    }
    return [pscustomobject]@{ GraphServicePrincipalId = $graphSp.id; Roles = $resolved }
}

function Invoke-TenantBootstrap {
    <#
    .SYNOPSIS
        Logique complete du bootstrap (App Registration + certificat + consentement admin).
        Utilisee par Bootstrap-TenantApp.ps1 (CLI) et par la GUI. Suppose qu'une connexion
        interactive avec les scopes delegues requis a deja ete etablie par l'appelant.
    #>
    param(
        [Parameter(Mandatory)][string]$ClientName,
        [ValidateRange(1, 10)][int]$CertValidityYears = 2,
        [scriptblock]$Log = { param($Message, $Color) Write-Host $Message -ForegroundColor $Color }
    )

    $requiredPermissions = @(
        'DeviceManagementManagedDevices.Read.All'
        'Device.Read.All'
        'User.Read.All'
        'Group.Create'
        'GroupMember.ReadWrite.All'
    )

    $context = Get-MgContext
    if (-not $context) { throw "Aucune session Graph active. Connect-WaveGraphInteractive doit etre appele avant Invoke-TenantBootstrap." }
    $tenantId = $context.TenantId
    & $Log "Connecte au tenant $tenantId" 'Green'

    # Everything from here on holds a live Graph connection - wrap in try/finally so a
    # failure partway through (cert ok but SP creation fails, a role consent POST fails,
    # etc.) still disconnects instead of leaving the app-only session open.
    try {
        & $Log "Resolution des permissions applicatives requises..." 'Cyan'
        $appRoles = Get-WaveGraphAppRoleIds -PermissionNames $requiredPermissions

        & $Log "Generation du certificat local (Cert:\CurrentUser\My)..." 'Cyan'
        $certSubject = "CN=IntuneWaveBuilder-$ClientName"
        $cert = New-SelfSignedCertificate `
            -Subject $certSubject `
            -CertStoreLocation 'Cert:\CurrentUser\My' `
            -KeyExportPolicy NonExportable `
            -KeySpec Signature `
            -KeyLength 2048 `
            -HashAlgorithm SHA256 `
            -NotAfter (Get-Date).AddYears($CertValidityYears)

        $certBase64 = [Convert]::ToBase64String($cert.GetRawCertData())
        & $Log "Certificat cree. Thumbprint: $($cert.Thumbprint)" 'Green'

        $appDisplayName = "IntuneWaveBuilder-$ClientName"
        & $Log "Creation de l'App Registration '$appDisplayName'..." 'Cyan'

        $appBody = @{
            displayName            = $appDisplayName
            signInAudience          = 'AzureADMyOrg'
            requiredResourceAccess = @(
                @{
                    resourceAppId  = $script:GraphAppId
                    resourceAccess = @($appRoles.Roles | ForEach-Object { @{ id = $_.Id; type = 'Role' } })
                }
            )
            keyCredentials = @(
                @{
                    type        = 'AsymmetricX509Cert'
                    usage       = 'Verify'
                    key         = $certBase64
                    displayName = 'IntuneWaveBuilder'
                }
            )
        } | ConvertTo-Json -Depth 10

        $app = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/applications' -Body $appBody
        & $Log "App Registration creee. AppId (ClientId): $($app.appId)" 'Green'

        $servicePrincipal = $null
        $attempts = 0
        while (-not $servicePrincipal -and $attempts -lt 6) {
            $attempts++
            try {
                Start-Sleep -Seconds 5
                $spBody = @{ appId = $app.appId } | ConvertTo-Json
                $servicePrincipal = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -Body $spBody
            } catch {
                & $Log "  Replication AAD en cours, nouvelle tentative ($attempts/6)..." 'DarkYellow'
            }
        }
        if (-not $servicePrincipal) { throw "Echec de creation du Service Principal apres plusieurs tentatives." }
        & $Log "Enterprise App (Service Principal) creee. Id: $($servicePrincipal.id)" 'Green'

        & $Log "Octroi du consentement admin pour les permissions applicatives..." 'Cyan'
        foreach ($role in $appRoles.Roles) {
            $assignBody = @{
                principalId = $servicePrincipal.id
                resourceId  = $appRoles.GraphServicePrincipalId
                appRoleId   = $role.Id
            } | ConvertTo-Json
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($servicePrincipal.id)/appRoleAssignedTo" -Body $assignBody | Out-Null
            & $Log "  Consenti : $($role.Name)" 'Green'
        }

        Save-WaveClientEntry -ClientName $ClientName -TenantId $tenantId -ClientId $app.appId -CertThumbprint $cert.Thumbprint
    } finally {
        Disconnect-MgGraph | Out-Null
    }

    return [pscustomobject]@{
        ClientName     = $ClientName
        TenantId       = $tenantId
        ClientId       = $app.appId
        CertThumbprint = $cert.Thumbprint
    }
}

function Invoke-NewWaveGroups {
    <#
    .SYNOPSIS
        Logique complete de creation des vagues (recuperation du pool Intune-managed,
        tirage sans remise, creation des groupes et ajout des membres).
        Utilisee par New-WaveGroups.ps1 (CLI) et par la GUI. Suppose qu'une connexion
        app-only (Connect-WaveGraphApp) et la confirmation du tenant ont deja ete faites
        par l'appelant.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('Device', 'User')][string]$TargetType,
        [Parameter(Mandatory)][string]$DeploymentName,
        [ValidateSet('All', 'Windows', 'iOS', 'Android', 'Linux', 'macOS')][string]$Platform = 'All',
        [Parameter(Mandatory)][int[]]$WavePercentages,
        [Parameter(Mandatory)][string]$LogDir,
        [scriptblock]$Log = { param($Message, $Color) Write-Host $Message -ForegroundColor $Color }
    )

    # --- 1. Recuperation des devices geres par Intune ---
    & $Log "Recuperation des devices Intune-managed..." 'Cyan'
    $selectFields = 'id,deviceName,azureADDeviceId,userId,userPrincipalName,operatingSystem,managementState'
    $managedDevices = Invoke-WaveGraphPaged -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$select=$selectFields"
    $managedDevices = $managedDevices | Where-Object { $_.managementState -eq 'managed' }

    if ($Platform -ne 'All') {
        $managedDevices = $managedDevices | Where-Object { $_.operatingSystem -eq $Platform }
    }
    & $Log "  $($managedDevices.Count) device(s) Intune-managed apres filtre plateforme." 'Green'

    if ($managedDevices.Count -eq 0) { throw "Aucun device Intune-managed ne correspond aux criteres. Abandon." }

    # --- 2. Construction du pool selon TargetType (une seule fois, partage entre toutes les vagues) ---
    $candidatePool = [System.Collections.Generic.List[object]]::new()

    if ($TargetType -eq 'Device') {
        & $Log "Resolution des objets Entra ID correspondants (mapping deviceId -> objectId)..." 'Cyan'
        $aadDevices = Invoke-WaveGraphPaged -Uri "https://graph.microsoft.com/v1.0/devices?`$select=id,deviceId"
        $deviceIdLookup = @{}
        foreach ($d in $aadDevices) { $deviceIdLookup[$d.deviceId] = $d.id }

        $skipped = 0
        $seen = @{}
        foreach ($md in $managedDevices) {
            if (-not $md.azureADDeviceId) { $skipped++; continue }
            $objectId = $deviceIdLookup[$md.azureADDeviceId]
            if (-not $objectId) { $skipped++; continue }
            if ($seen.ContainsKey($objectId)) { continue }
            $seen[$objectId] = $true
            $candidatePool.Add([pscustomobject]@{ Id = $objectId; Name = $md.deviceName })
        }
        if ($skipped -gt 0) { & $Log "  $skipped device(s) Intune ignore(s) (pas d'objet Entra ID resolu)." 'DarkYellow' }
    }
    else {
        & $Log "Resolution des proprietaires (userType Member, compte actif)..." 'Cyan'
        $userIds = $managedDevices | Where-Object { $_.userId } | Select-Object -ExpandProperty userId -Unique

        $skipped = 0
        foreach ($uid in $userIds) {
            try {
                $user = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$uid`?`$select=id,displayName,userPrincipalName,userType,accountEnabled"
            } catch {
                $skipped++; continue
            }
            if ($user.userType -ne 'Member' -or -not $user.accountEnabled) { $skipped++; continue }
            $candidatePool.Add([pscustomobject]@{ Id = $user.id; Name = $user.userPrincipalName })
        }
        if ($skipped -gt 0) { & $Log "  $skipped utilisateur(s) ignore(s) (guest / desactive / introuvable)." 'DarkYellow' }
    }

    if ($candidatePool.Count -eq 0) { throw "Pool de selection vide apres filtrage. Abandon." }
    & $Log "Pool final : $($candidatePool.Count) $TargetType(s) eligible(s)." 'Green'

    # --- 3. Creation des groupes, une vague a la fois ---
    $prefix = if ($TargetType -eq 'Device') { 'ADSG' } else { 'AUSG' }
    $safeDeployment = ($DeploymentName -replace '[^A-Za-z0-9]+', '-').Trim('-')
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

    $summary = [System.Collections.Generic.List[object]]::new()

    $originalTotal = $candidatePool.Count
    $remainingPool = [System.Collections.Generic.List[object]]::new($candidatePool)
    $waveCount = $WavePercentages.Count

    for ($waveNumber = 1; $waveNumber -le $waveCount; $waveNumber++) {
        $percentage = $WavePercentages[$waveNumber - 1]
        & $Log "-- Vague $waveNumber / $waveCount ($percentage%) --" 'Cyan'

        $sampleSize = [math]::Round($originalTotal * $percentage / 100.0)
        if ($sampleSize -gt $remainingPool.Count) {
            & $Log "  Pool restant insuffisant ($($remainingPool.Count) disponible(s) pour $sampleSize demande(s)) -> selection plafonnee." 'DarkYellow'
            $sampleSize = $remainingPool.Count
        }
        if ($sampleSize -eq 0) {
            & $Log "  Aucun element disponible pour cette vague (pool epuise ou $percentage% de $originalTotal donne 0), vague ignoree." 'DarkYellow'
            continue
        }
        $selected = $remainingPool | Get-Random -Count $sampleSize
        foreach ($item in $selected) { $remainingPool.Remove($item) | Out-Null }
        & $Log "  Tirage aleatoire (sans remise) : $sampleSize / $originalTotal selectionne(s). Pool restant apres cette vague : $($remainingPool.Count)." 'Green'

        $baseGroupName = "${prefix}_Intune_${safeDeployment}_Wave${waveNumber}"
        $groupName = $baseGroupName
        $existing = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$groupName'").value
        if ($existing) {
            $suffix = Get-Date -Format 'yyyyMMdd-HHmm'
            $groupName = "${baseGroupName}_${suffix}"
            & $Log "  Un groupe '$baseGroupName' existe deja -> nouveau nom : $groupName" 'DarkYellow'
        }

        & $Log "  Creation du groupe '$groupName'..." 'Cyan'
        $mailNickname = ($groupName -replace '[^A-Za-z0-9]', '')
        $groupBody = @{
            displayName     = $groupName
            mailEnabled     = $false
            mailNickname    = $mailNickname
            securityEnabled = $true
            groupTypes      = @()
            description     = "IntuneWaveBuilder - $TargetType - $percentage% - Wave $waveNumber - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        } | ConvertTo-Json

        $group = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/groups' -Body $groupBody
        & $Log "  Groupe cree. Id: $($group.id)" 'Green'

        $logRows = [System.Collections.Generic.List[object]]::new()
        $failures = 0
        foreach ($member in $selected) {
            $refBody = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($member.Id)" } | ConvertTo-Json
            try {
                Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/groups/$($group.id)/members/`$ref" -Body $refBody | Out-Null
                $logRows.Add([pscustomobject]@{ ObjectId = $member.Id; Name = $member.Name; Status = 'Added' })
            } catch {
                $failures++
                $logRows.Add([pscustomobject]@{ ObjectId = $member.Id; Name = $member.Name; Status = "Failed: $($_.Exception.Message)" })
            }
        }
        if ($failures -gt 0) { & $Log "  $failures ajout(s) en echec (voir le log)." 'DarkYellow' }

        $logPath = Join-Path $LogDir "$groupName.csv"
        $logRows | Export-Csv -Path $logPath -NoTypeInformation -Encoding UTF8

        $summary.Add([pscustomobject]@{
            Wave         = $waveNumber
            Percentage   = $percentage
            GroupName    = $groupName
            GroupId      = $group.id
            MembersAdded = $logRows.Count - $failures
            MembersTotal = $logRows.Count
            Log          = $logPath
        })
    }

    return $summary
}
