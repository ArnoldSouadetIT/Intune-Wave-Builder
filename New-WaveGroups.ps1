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

    La logique de recuperation du pool et de creation des groupes est partagee avec la GUI
    (Show-WaveBuilderGui.ps1) via la fonction Invoke-NewWaveGroups de WaveGroups.Common.ps1.

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
    Filtre optionnel de plateforme : All, Windows, iOS, Android, Linux, macOS. Defaut : All.
    Si TargetType = Device et que ce parametre n'est pas fourni, le script le demande de maniere interactive.

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

    [ValidateSet('All', 'Windows', 'iOS', 'Android', 'Linux', 'macOS')]
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

if ($TargetType -eq 'Device' -and -not $PSBoundParameters.ContainsKey('Platform')) {
    $Platform = $null
    while (-not $Platform) {
        $raw = Read-Host "OS cible - reponses acceptees : Windows / Android / iOS / Linux / macOS (ou 'All' pour ne pas filtrer)"
        $Platform = Resolve-WavePlatform -Raw $raw
        if (-not $Platform) {
            Write-Host "Reponse invalide. Entre 'Windows', 'Android', 'iOS', 'Linux', 'macOS' ou 'All'." -ForegroundColor Red
        }
    }
    Write-Host "OS retenu : $Platform" -ForegroundColor Green
}

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

$logDir = Join-Path $PSScriptRoot 'Logs'
$summary = Invoke-NewWaveGroups `
    -TargetType $TargetType `
    -DeploymentName $DeploymentName `
    -Platform $Platform `
    -WavePercentages $wavePercentages `
    -LogDir $logDir

Disconnect-MgGraph | Out-Null

Write-Host ""
Write-Host "== Termine ==" -ForegroundColor Cyan
$summary | Format-Table -AutoSize
