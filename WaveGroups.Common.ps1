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

function Confirm-WaveTenant {
    param(
        [Parameter(Mandatory)][string]$ExpectedTenantId
    )
    $org = (Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id,displayName,verifiedDomains').value | Select-Object -First 1
    if (-not $org) { throw "Impossible de recuperer les informations d'organisation (endpoint /organization) pour verifier le tenant." }

    $primaryDomain = ($org.verifiedDomains | Where-Object { $_.isDefault }).name
    if (-not $primaryDomain) { $primaryDomain = ($org.verifiedDomains | Select-Object -First 1).name }

    Write-Host ""
    Write-Host "=====================================================" -ForegroundColor Yellow
    Write-Host " Tenant connecte :" -ForegroundColor Yellow
    Write-Host "   Nom          : $($org.displayName)" -ForegroundColor Yellow
    Write-Host "   Domaine      : $primaryDomain" -ForegroundColor Yellow
    Write-Host "   TenantId     : $($org.id)" -ForegroundColor Yellow
    Write-Host "=====================================================" -ForegroundColor Yellow

    if ($org.id -ne $ExpectedTenantId) {
        throw "Le TenantId retourne par /organization ($($org.id)) ne correspond pas au TenantId fourni ($ExpectedTenantId). Abandon par securite."
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
