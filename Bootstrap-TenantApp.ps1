<#
.SYNOPSIS
    Cree, dans le tenant client courant, une App Registration dediee pour Intune Wave Builder
    avec permissions applicatives minimales, un certificat d'authentification, et
    accorde le consentement admin automatiquement.

.DESCRIPTION
    A executer UNE FOIS PAR TENANT CLIENT, connecte avec un compte Global Admin
    (ou Application Administrator + Privileged Role Administrator).
    Cree :
      - Un App Registration isole pour ce client (aucun partage entre clients)
      - Un certificat auto-signe stocke dans Cert:\CurrentUser\My (cle privee non exportable)
      - Le Service Principal (Enterprise App) associe
      - Le consentement admin pour les permissions applicatives minimales requises
      - Une entree locale de reference dans %LOCALAPPDATA%\IntuneWaveBuilder\clients.json
        (TenantId/ClientId/CertThumbprint a copier-coller dans New-WaveGroups.ps1).

.PARAMETER ClientName
    Nom court et unique du client (utilise pour retrouver la config plus tard). Ex: "Contoso".

.PARAMETER CertValidityYears
    Duree de validite du certificat genere. Defaut : 2 ans.

.EXAMPLE
    .\Bootstrap-TenantApp.ps1 -ClientName "Contoso"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ClientName,

    [ValidateRange(1, 10)]
    [int]$CertValidityYears = 2
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WaveGroups.Common.ps1')

$RequiredPermissions = @(
    'DeviceManagementManagedDevices.Read.All'
    'Device.Read.All'
    'User.Read.All'
    'Group.Create'
    'GroupMember.ReadWrite.All'
)

Write-Host "== Bootstrap Intune Wave Builder pour '$ClientName' ==" -ForegroundColor Cyan
Write-Host "Connexion interactive requise (Global Admin / Application Administrator + Privileged Role Administrator)." -ForegroundColor Yellow
Connect-WaveGraphInteractive -Scopes @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All')

$context = Get-MgContext
$tenantId = $context.TenantId
Write-Host "Connecte au tenant $tenantId" -ForegroundColor Green

Write-Host "Resolution des permissions applicatives requises..." -ForegroundColor Cyan
$appRoles = Get-WaveGraphAppRoleIds -PermissionNames $RequiredPermissions

Write-Host "Generation du certificat local (Cert:\CurrentUser\My)..." -ForegroundColor Cyan
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
Write-Host "Certificat cree. Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green

$appDisplayName = "IntuneWaveBuilder-$ClientName"
Write-Host "Creation de l'App Registration '$appDisplayName'..." -ForegroundColor Cyan

$appBody = @{
    displayName          = $appDisplayName
    signInAudience        = 'AzureADMyOrg'
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
Write-Host "App Registration creee. AppId (ClientId): $($app.appId)" -ForegroundColor Green

# Laisse le temps a la replication AAD avant de creer le service principal
$servicePrincipal = $null
$attempts = 0
while (-not $servicePrincipal -and $attempts -lt 6) {
    $attempts++
    try {
        Start-Sleep -Seconds 5
        $spBody = @{ appId = $app.appId } | ConvertTo-Json
        $servicePrincipal = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -Body $spBody
    } catch {
        Write-Host "  Replication AAD en cours, nouvelle tentative ($attempts/6)..." -ForegroundColor DarkYellow
    }
}
if (-not $servicePrincipal) { throw "Echec de creation du Service Principal apres plusieurs tentatives." }
Write-Host "Enterprise App (Service Principal) creee. Id: $($servicePrincipal.id)" -ForegroundColor Green

Write-Host "Octroi du consentement admin pour les permissions applicatives..." -ForegroundColor Cyan
foreach ($role in $appRoles.Roles) {
    $assignBody = @{
        principalId = $servicePrincipal.id
        resourceId  = $appRoles.GraphServicePrincipalId
        appRoleId   = $role.Id
    } | ConvertTo-Json
    Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($servicePrincipal.id)/appRoleAssignedTo" -Body $assignBody | Out-Null
    Write-Host "  Consenti : $($role.Name)" -ForegroundColor Green
}

Save-WaveClientEntry -ClientName $ClientName -TenantId $tenantId -ClientId $app.appId -CertThumbprint $cert.Thumbprint

Disconnect-MgGraph | Out-Null

Write-Host ""
Write-Host "== Termine ==" -ForegroundColor Cyan
Write-Host "Client        : $ClientName"
Write-Host "TenantId      : $tenantId"
Write-Host "ClientId      : $($app.appId)"
Write-Host "Thumbprint    : $($cert.Thumbprint)"
Write-Host "Enregistre dans : $script:WaveRegistryPath (reference locale)"
Write-Host ""
Write-Host "Utilise ces valeurs avec New-WaveGroups.ps1 :" -ForegroundColor Green
Write-Host "  -TenantId '$tenantId' -ClientId '$($app.appId)' -CertThumbprint '$($cert.Thumbprint)'" -ForegroundColor Green
