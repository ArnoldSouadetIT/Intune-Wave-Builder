<#
.SYNOPSIS
    Cree en une seule execution plusieurs groupes de securite Entra ID (assigned), un par vague,
    chacun peuple aleatoirement avec un pourcentage de devices ou d'utilisateurs geres par Intune.

.DESCRIPTION
    Se connecte en app-only (certificat) via l'App Registration creee par Bootstrap-TenantApp.ps1.
    Le pool de selection est TOUJOURS restreint aux devices geres par Intune (managementState = managed) :
      - Mode Device : les objets device Entra ID correspondants (pas les devices AAD-registered seuls)
      - Mode User   : les proprietaires principaux de ces devices, filtres sur userType 'Member'
                      et compte actif (exclut guests, comptes de service/generiques)
    Le pool complet est recupere UNE SEULE FOIS. Chaque vague tire son pourcentage (calcule sur la taille
    du pool ORIGINAL) SANS REMISE : une fois qu'une entite est assignee a une vague, elle est retiree du
    pool et ne peut plus etre selectionnee par une vague suivante. Pas de doublon entre vagues, et si les
    pourcentages additionnes font 100%, la totalite du pool est couverte a l'issue de la derniere vague.
    Si le pool restant est insuffisant pour honorer le pourcentage demande (ex: pourcentages > 100% au
    total), la selection est plafonnee au nombre d'entites encore disponibles. Si un groupe du meme nom
    existe deja, un suffixe horodate est ajoute pour eviter tout ecrasement silencieux.

    Le script demande de maniere interactive le nombre de vagues, puis le pourcentage de chacune.

    Par securite, apres connexion, le script affiche le nom/domaine/TenantId de l'organisation
    reellement connectee (via GET /organization) et demande une confirmation explicite avant toute
    creation de groupe ou ajout de membre - protection contre un copier-coller de TenantId/ClientId
    errone qui pointerait vers le mauvais client.

.PARAMETER TenantId
    Tenant cible (affiche par Bootstrap-TenantApp.ps1 a la fin de son execution).

.PARAMETER ClientId
    AppId de l'App Registration dediee (affiche par Bootstrap-TenantApp.ps1).

.PARAMETER CertThumbprint
    Thumbprint du certificat local (affiche par Bootstrap-TenantApp.ps1).

.PARAMETER TargetType
    'Device' ou 'User'. Optionnel : si omis, le script le demande de maniere interactive
    (accepte aussi 'devices'/'users' au pluriel et les raccourcis 'D'/'U', insensible a la casse).

.PARAMETER DeploymentName
    Nom du deploiement (utilise dans le nom de chaque groupe de vague).

.PARAMETER Platform
    Filtre optionnel de plateforme : All, Windows, iOS, Android, macOS. Defaut : All.

.EXAMPLE
    .\New-WaveGroups.ps1 -TenantId $tid -ClientId $cid -CertThumbprint $thumb -TargetType Device -DeploymentName "Win32AppX" -Platform Windows
    # Le script demande ensuite : nombre de vagues, puis le % de chaque vague.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$ClientId,

    [Parameter(Mandatory)]
    [string]$CertThumbprint,

    [string]$TargetType,

    [Parameter(Mandatory)]
    [string]$DeploymentName,

    [ValidateSet('All', 'Windows', 'iOS', 'Android', 'macOS')]
    [string]$Platform = 'All'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WaveGroups.Common.ps1')

# --- 0. Questions interactives : type de cible, nombre de vagues, pourcentage de chacune ---
$TargetType = Resolve-WaveTargetType -Raw $TargetType
while (-not $TargetType) {
    $raw = Read-Host "Type de cible - reponses acceptees : Device / D / User / U"
    $TargetType = Resolve-WaveTargetType -Raw $raw
    if (-not $TargetType) {
        Write-Host "Reponse invalide. Entre 'Device', 'D', 'User' ou 'U' (le pluriel est aussi accepte)." -ForegroundColor Red
    }
}
Write-Host "Type de cible retenu : $TargetType" -ForegroundColor Green

[int]$waveCount = 0
while ($waveCount -lt 1) {
    $raw = Read-Host "Nombre total de vagues a creer"
    if (-not [int]::TryParse($raw, [ref]$waveCount) -or $waveCount -lt 1) {
        Write-Host "Valeur invalide, entre un entier >= 1." -ForegroundColor Red
        $waveCount = 0
    }
}

$wavePercentages = [System.Collections.Generic.List[int]]::new()
for ($i = 1; $i -le $waveCount; $i++) {
    [int]$pct = 0
    while ($pct -lt 1 -or $pct -gt 100) {
        $raw = Read-Host "Pourcentage pour la Vague $i (1-100)"
        if (-not [int]::TryParse($raw, [ref]$pct) -or $pct -lt 1 -or $pct -gt 100) {
            Write-Host "Valeur invalide, entre un entier entre 1 et 100." -ForegroundColor Red
            $pct = 0
        }
    }
    $wavePercentages.Add($pct)
}

Write-Host "== New-WaveGroups : $TargetType | $DeploymentName | $waveCount vague(s) : $($wavePercentages -join '%, ')% | Platform=$Platform ==" -ForegroundColor Cyan
Connect-WaveGraphApp -TenantId $TenantId -ClientId $ClientId -CertThumbprint $CertThumbprint

try {
    Confirm-WaveTenant -ExpectedTenantId $TenantId
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Disconnect-MgGraph | Out-Null
    exit 1
}

# --- 1. Recuperation des devices geres par Intune ---
Write-Host "Recuperation des devices Intune-managed..." -ForegroundColor Cyan
$selectFields = 'id,deviceName,azureADDeviceId,userId,userPrincipalName,operatingSystem,managementState'
$managedDevices = Invoke-WaveGraphPaged -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$select=$selectFields"
$managedDevices = $managedDevices | Where-Object { $_.managementState -eq 'managed' }

if ($Platform -ne 'All') {
    $managedDevices = $managedDevices | Where-Object { $_.operatingSystem -eq $Platform }
}
Write-Host "  $($managedDevices.Count) device(s) Intune-managed apres filtre plateforme." -ForegroundColor Green

if ($managedDevices.Count -eq 0) { throw "Aucun device Intune-managed ne correspond aux criteres. Abandon." }

# --- 2. Construction du pool selon TargetType (une seule fois, partage entre toutes les vagues) ---
$candidatePool = [System.Collections.Generic.List[object]]::new()

if ($TargetType -eq 'Device') {
    Write-Host "Resolution des objets Entra ID correspondants (mapping deviceId -> objectId)..." -ForegroundColor Cyan
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
    if ($skipped -gt 0) { Write-Host "  $skipped device(s) Intune ignore(s) (pas d'objet Entra ID resolu)." -ForegroundColor DarkYellow }
}
else {
    Write-Host "Resolution des proprietaires (userType Member, compte actif)..." -ForegroundColor Cyan
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
    if ($skipped -gt 0) { Write-Host "  $skipped utilisateur(s) ignore(s) (guest / desactive / introuvable)." -ForegroundColor DarkYellow }
}

if ($candidatePool.Count -eq 0) { throw "Pool de selection vide apres filtrage. Abandon." }
Write-Host "Pool final : $($candidatePool.Count) $TargetType(s) eligible(s)." -ForegroundColor Green

# --- 3. Creation des groupes, une vague a la fois ---
$prefix = if ($TargetType -eq 'Device') { 'ADSG' } else { 'AUSG' }
$safeDeployment = ($DeploymentName -replace '[^A-Za-z0-9]+', '-').Trim('-')
$logDir = Join-Path $PSScriptRoot 'Logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$summary = [System.Collections.Generic.List[object]]::new()

$originalTotal = $candidatePool.Count
$remainingPool = [System.Collections.Generic.List[object]]::new($candidatePool)

for ($waveNumber = 1; $waveNumber -le $waveCount; $waveNumber++) {
    $percentage = $wavePercentages[$waveNumber - 1]
    Write-Host ""
    Write-Host "-- Vague $waveNumber / $waveCount ($percentage%) --" -ForegroundColor Cyan

    $sampleSize = [math]::Round($originalTotal * $percentage / 100.0)
    if ($sampleSize -gt $remainingPool.Count) {
        Write-Host "  Pool restant insuffisant ($($remainingPool.Count) disponible(s) pour $sampleSize demande(s)) -> selection plafonnee." -ForegroundColor DarkYellow
        $sampleSize = $remainingPool.Count
    }
    if ($sampleSize -eq 0) {
        Write-Host "  Aucun element disponible pour cette vague (pool epuise ou $percentage% de $originalTotal donne 0), vague ignoree." -ForegroundColor DarkYellow
        continue
    }
    $selected = $remainingPool | Get-Random -Count $sampleSize
    foreach ($item in $selected) { $remainingPool.Remove($item) | Out-Null }
    Write-Host "  Tirage aleatoire (sans remise) : $sampleSize / $originalTotal selectionne(s). Pool restant apres cette vague : $($remainingPool.Count)." -ForegroundColor Green

    $baseGroupName = "${prefix}_Intune_${safeDeployment}_Wave${waveNumber}"
    $groupName = $baseGroupName
    $existing = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$groupName'").value
    if ($existing) {
        $suffix = Get-Date -Format 'yyyyMMdd-HHmm'
        $groupName = "${baseGroupName}_${suffix}"
        Write-Host "  Un groupe '$baseGroupName' existe deja -> nouveau nom : $groupName" -ForegroundColor DarkYellow
    }

    Write-Host "  Creation du groupe '$groupName'..." -ForegroundColor Cyan
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
    Write-Host "  Groupe cree. Id: $($group.id)" -ForegroundColor Green

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
    if ($failures -gt 0) { Write-Host "  $failures ajout(s) en echec (voir le log)." -ForegroundColor DarkYellow }

    $logPath = Join-Path $logDir "$groupName.csv"
    $logRows | Export-Csv -Path $logPath -NoTypeInformation -Encoding UTF8

    $summary.Add([pscustomobject]@{
        Wave        = $waveNumber
        Percentage  = $percentage
        GroupName   = $groupName
        GroupId     = $group.id
        MembersAdded = $logRows.Count - $failures
        MembersTotal = $logRows.Count
        Log         = $logPath
    })
}

Disconnect-MgGraph | Out-Null

Write-Host ""
Write-Host "== Termine ==" -ForegroundColor Cyan
$summary | Format-Table -AutoSize
