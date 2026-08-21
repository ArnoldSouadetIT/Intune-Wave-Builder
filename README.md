# IntuneWaveBuilder

Outil PowerShell (CLI + interface graphique) pour déployer des mises à jour ou des applications Intune **par vagues**, en créant automatiquement des groupes de sécurité Entra ID peuplés aléatoirement à partir des appareils ou utilisateurs réellement gérés par Intune.

Chaque tenant client est isolé : une App Registration dédiée, authentifiée par certificat, avec des permissions Graph minimales.

## Pourquoi

Déployer une mise à jour ou une application à 100% du parc en une seule fois est risqué. IntuneWaveBuilder découpe la cible en plusieurs vagues (ex. 10% / 20% / 70%) et crée un groupe de sécurité Entra ID par vague, chacun assigné à une politique/appli Intune séparée — permettant de valider une vague avant de passer à la suivante.

## Fonctionnalités

- **Vagues sans doublon** : le pool d'appareils/utilisateurs éligibles est tiré une seule fois, réparti entre les vagues *sans remise* — aucune entité ne peut se retrouver dans deux vagues.
- **Ciblage Device ou User**, avec filtre de plateforme (Windows / iOS / Android / Linux / macOS) en mode Device.
- **Pool toujours restreint aux appareils gérés par Intune** (`managementState = managed`), jamais aux appareils simplement inscrits dans Entra ID.
- **Confirmation du tenant** avant toute création : le nom, le domaine et le TenantId de l'organisation réellement connectée sont affichés et doivent être confirmés — protection contre un mauvais choix de client.
- **Isolation par client** : chaque tenant a sa propre App Registration, son propre certificat, aucun partage entre clients.
- **Log CSV par groupe** (membres ajoutés / échecs) pour audit.
- **Interface graphique** (dark mode) en plus des scripts CLI, pilotant exactement la même logique.

## Architecture

```
Bootstrap-TenantApp.ps1   CLI - bootstrap d'un nouveau client (App Registration + cert)
New-WaveGroups.ps1        CLI - création des vagues pour un client déjà bootstrappé
Show-WaveBuilderGui.ps1   GUI (WPF) - couvre les deux flux ci-dessus + registre clients + logs
WaveGroups.Common.ps1     Logique partagée (appels Graph, aucune duplication CLI/GUI)
Logs/                     CSV générés par vague (ignorés par git - données clients réelles)
```

`WaveGroups.Common.ps1` contient toute la logique métier (`Invoke-TenantBootstrap`, `Invoke-NewWaveGroups`, `Confirm-WaveTenant`, ...). Les scripts CLI et la GUI ne sont que deux façons différentes de piloter ces mêmes fonctions — aucune divergence de comportement entre les deux.

## Prérequis

- Windows PowerShell 5.1 ou PowerShell 7+ (les deux sont supportés et testés, y compris pour la GUI).
- Module `Microsoft.Graph.Authentication` (installé automatiquement au premier lancement si absent).
- Pour le **bootstrap** d'un client : un compte **Global Administrator**, ou **Application Administrator + Privileged Role Administrator**, dans le tenant cible.
- Pour la **création de vagues** : aucun compte interactif requis — l'authentification se fait via le certificat créé au bootstrap.

## Démarrage rapide

### 1. Bootstrap d'un nouveau client (une seule fois par tenant)

```powershell
.\Bootstrap-TenantApp.ps1 -ClientName "Contoso"
```

Ouvre une connexion interactive (le compte doit avoir les droits ci-dessus), puis crée :

- une App Registration dédiée (`IntuneWaveBuilder-Contoso`) avec les permissions applicatives minimales :
  - `DeviceManagementManagedDevices.Read.All`
  - `Device.Read.All`
  - `User.Read.All`
  - `Group.Create`
  - `GroupMember.ReadWrite.All`
- un certificat auto-signé local (`Cert:\CurrentUser\My`, clé privée non exportable)
- le Service Principal (Enterprise App) associé
- le consentement admin pour les permissions ci-dessus
- une entrée locale dans `%LOCALAPPDATA%\IntuneWaveBuilder\clients.json` (TenantId / ClientId / Thumbprint)

### 2. Créer des vagues

```powershell
.\New-WaveGroups.ps1 -TenantId '<tenant-id>' -ClientId '<client-id>' -CertThumbprint '<thumbprint>' `
    -TargetType Device -DeploymentName "Win32AppX" -Platform Windows
```

Le script demande ensuite le nombre de vagues et le pourcentage de chacune, affiche le tenant réellement connecté pour confirmation, puis crée un groupe `ADSG_Intune_<Deploiement>_Wave<N>` (ou `AUSG_...` en mode User) par vague, peuplé aléatoirement.

### 3. Ou : tout faire depuis l'interface graphique

```powershell
.\Show-WaveBuilderGui.ps1
```

4 onglets : **Nouveau client (Bootstrap)**, **Créer des vagues**, **Registre clients** (gérer les clients déjà bootstrappés), **Logs** (parcourir les CSV générés). Les appels Graph s'exécutent en arrière-plan pour ne jamais geler l'interface.

## Sécurité

- Chaque client a sa **propre** App Registration et son **propre** certificat — aucun credential partagé entre tenants.
- Les permissions applicatives accordées sont **minimales** et listées explicitement dans `Bootstrap-TenantApp.ps1` / `Invoke-TenantBootstrap`.
- Avant toute création de groupe, le tenant **réellement connecté** est affiché et doit être confirmé explicitement — protection contre un `TenantId`/`ClientId` copié-collé par erreur.
- Le fichier `clients.json` (`%LOCALAPPDATA%\IntuneWaveBuilder\`) n'est qu'une **référence locale** (Tenant/Client/Thumbprint) : le supprimer ou retirer une entrée depuis l'onglet "Registre clients" de la GUI ne supprime **pas** l'App Registration ni le certificat côté tenant.
- Les logs CSV (`Logs/`) contiennent des données réelles de clients (noms d'appareils/utilisateurs, ObjectId) et sont exclus du dépôt via `.gitignore`.

## Compatibilité

Testé sous **Windows PowerShell 5.1** et **PowerShell 7**, y compris l'interface graphique WPF (une différence de comportement de rendu entre .NET Framework et .NET a été identifiée et corrigée — voir l'historique des commits pour le détail).
