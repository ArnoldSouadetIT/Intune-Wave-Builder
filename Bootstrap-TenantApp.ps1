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

    La logique de bootstrap est partagee avec la GUI (Show-WaveBuilderGui.ps1) via la fonction
    Invoke-TenantBootstrap de WaveGroups.Common.ps1.

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

Write-Host "== Bootstrap Intune Wave Builder pour '$ClientName' ==" -ForegroundColor Cyan
Write-Host "Connexion interactive requise (Global Admin / Application Administrator + Privileged Role Administrator)." -ForegroundColor Yellow
Connect-WaveGraphInteractive -Scopes @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All')

$result = Invoke-TenantBootstrap -ClientName $ClientName -CertValidityYears $CertValidityYears

Write-Host ""
Write-Host "== Termine ==" -ForegroundColor Cyan
Write-Host "Client        : $($result.ClientName)"
Write-Host "TenantId      : $($result.TenantId)"
Write-Host "ClientId      : $($result.ClientId)"
Write-Host "Thumbprint    : $($result.CertThumbprint)"
Write-Host "Enregistre dans : $script:WaveRegistryPath (reference locale)"
Write-Host ""
Write-Host "Utilise ces valeurs avec New-WaveGroups.ps1 :" -ForegroundColor Green
Write-Host "  -TenantId '$($result.TenantId)' -ClientId '$($result.ClientId)' -CertThumbprint '$($result.CertThumbprint)'" -ForegroundColor Green
