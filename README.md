**English** | [Français](README.fr.md)

# IntuneWaveBuilder

PowerShell tool (CLI + GUI) for rolling out Intune updates or applications **in waves**, by automatically creating Entra ID security groups randomly populated from devices or users actually managed by Intune.

Each client tenant is isolated: a dedicated App Registration, certificate-authenticated, with minimal Graph permissions.

## Why

Deploying an update or application to 100% of a fleet in one shot is risky. IntuneWaveBuilder splits the target into several waves (e.g. 10% / 20% / 70%) and creates one Entra ID security group per wave, each assigned to a separate Intune policy/app — letting you validate one wave before moving to the next.

## Features

- **No-duplicate waves**: the pool of eligible devices/users is pulled once and split across waves *without replacement* — no entity can end up in two waves.
- **Device or User targeting**, with a platform filter (Windows / iOS / Android / Linux / macOS) in Device mode.
- **Pool always restricted to Intune-managed devices** (`managementState = managed`), never to devices merely registered in Entra ID.
- **Tenant confirmation** before any creation: the display name, domain, and TenantId of the actually-connected organization are shown and must be confirmed — protection against picking the wrong client.
- **Per-client isolation**: each tenant has its own App Registration and its own certificate, nothing shared between clients.
- **Per-group CSV log** (members added / failures) for auditing.
- **Graphical interface** (dark mode) in addition to the CLI scripts, driving the exact same logic.

## Architecture

```
Bootstrap-TenantApp.ps1   CLI - bootstraps a new client (App Registration + certificate)
New-WaveGroups.ps1        CLI - creates the waves for an already-bootstrapped client
Show-WaveBuilderGui.ps1   GUI (WPF) - covers both flows above, plus client registry and logs
WaveGroups.Common.ps1     Shared logic (Graph calls, no CLI/GUI duplication)
Logs/                     Per-wave CSVs (git-ignored - contains real client data)
```

`WaveGroups.Common.ps1` holds all the business logic (`Invoke-TenantBootstrap`, `Invoke-NewWaveGroups`, `Confirm-WaveTenant`, ...). The CLI scripts and the GUI are just two different front ends driving the same functions — no behavior drift between them.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+ (both supported and tested, including the GUI).
- `Microsoft.Graph.Authentication` module (auto-installed on first run if missing).
- For **bootstrapping** a client: a **Global Administrator** account, or **Application Administrator + Privileged Role Administrator**, in the target tenant.
- For **creating waves**: no interactive account needed — authentication uses the certificate created during bootstrap.

## Quick start

### 1. Bootstrap a new client (once per tenant)

```powershell
.\Bootstrap-TenantApp.ps1 -ClientName "Contoso"
```

Opens an interactive sign-in (the account needs the rights listed above), then creates:

- a dedicated App Registration (`IntuneWaveBuilder-Contoso`) with minimal application permissions:
  - `DeviceManagementManagedDevices.Read.All`
  - `Device.Read.All`
  - `User.Read.All`
  - `Group.Create`
  - `GroupMember.ReadWrite.All`
- a local self-signed certificate (`Cert:\CurrentUser\My`, non-exportable private key)
- the associated Service Principal (Enterprise App)
- admin consent for the permissions above
- a local entry in `%LOCALAPPDATA%\IntuneWaveBuilder\clients.json` (TenantId / ClientId / Thumbprint)

### 2. Create waves

```powershell
.\New-WaveGroups.ps1 -TenantId '<tenant-id>' -ClientId '<client-id>' -CertThumbprint '<thumbprint>' `
    -TargetType Device -DeploymentName "Win32AppX" -Platform Windows
```

The script then asks for the number of waves and each wave's percentage, displays the actually-connected tenant for confirmation, then creates one `ADSG_Intune_<Deployment>_Wave<N>` group per wave (or `AUSG_...` in User mode), randomly populated.

### 3. Or: do it all from the GUI

```powershell
.\Show-WaveBuilderGui.ps1
```

4 tabs: **Nouveau client (Bootstrap)**, **Créer des vagues**, **Registre clients** (manage already-bootstrapped clients), **Logs** (browse the generated CSVs). Graph calls run in the background so the UI never freezes.

## Security

- Each client has its **own** App Registration and its **own** certificate — no credential shared between tenants.
- The granted application permissions are **minimal** and explicitly listed in `Bootstrap-TenantApp.ps1` / `Invoke-TenantBootstrap`.
- Before any group creation, the **actually-connected** tenant is displayed and must be explicitly confirmed — protection against a copy-pasted `TenantId`/`ClientId` mistake.
- The `clients.json` file (`%LOCALAPPDATA%\IntuneWaveBuilder\`) is only a **local reference** (Tenant/Client/Thumbprint): deleting it, or removing an entry from the GUI's "Registre clients" tab, does **not** delete the App Registration or the certificate on the tenant side.
- CSV logs (`Logs/`) contain real client data (device/user names, ObjectId) and are excluded from the repo via `.gitignore`.

## Compatibility

Tested on **Windows PowerShell 5.1** and **PowerShell 7**, including the WPF GUI (a .NET Framework vs .NET rendering-behavior difference was found and fixed — see the commit history for details).
