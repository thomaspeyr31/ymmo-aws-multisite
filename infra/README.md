# Infra Ymmo — déploiement répétable

Tout est **Infrastructure as Code** : Terraform (ressources AWS) + Ansible (configuration des VM
via SSM). **Aucune action console ni PowerShell manuel.** Un seul script reconstruit tout depuis zéro.

```
infra/
├── terraform/environments/demo/   # toute l'infra AWS (VPC, EC2, TGW, firewall, VPN…)
├── ansible/                       # configuration des VM (AD, jonctions, partages, strongSwan)
└── deploy-all.sh                  # ORCHESTRATEUR : apply -> AD -> jonctions -> partages -> VPN
```

## 1. Prérequis (poste de pilotage — macOS)

> **Pas besoin de PowerShell** sur le Mac : tout le PowerShell s'exécute **sur les EC2 Windows**,
> piloté par Ansible (`win_*`) à travers **SSM**. Pas de Docker non plus.

| # | Outil | Rôle | Installation | Version testée |
|---|-------|------|--------------|----------------|
| 1 | Homebrew | gestionnaire de paquets | cf. https://brew.sh | — |
| 2 | Terraform | provisionne l'infra AWS | `brew install terraform` | 1.14.1 (≥ 1.10) |
| 3 | AWS CLI v2 | API AWS + attentes SSM | `brew install awscli` | 2.34 |
| 4 | Session Manager Plugin | tunnel SSM (Ansible + RDP) | `brew install --cask session-manager-plugin` | 1.2.804 |
| 5 | Ansible (core) | configure les VM | `brew install ansible` | core 2.16.12 |
| 6 | boto3 + botocore | requis par `amazon.aws`/`community.aws` (connexion `aws_ssm`) | `python3 -m pip install boto3 botocore` | — |
| 7 | Collections Ansible | `microsoft.ad`, `ansible.windows`, `amazon.aws`, `community.aws` | `cd ansible && ansible-galaxy collection install -r requirements.yml` | — |

> ⚠️ `boto3` doit être visible par **le Python qu'utilise Ansible**. Le plus robuste = un **venv** :
> ```bash
> python3 -m venv .venv && source .venv/bin/activate
> pip install ansible boto3 botocore
> ```
> (tu as alors Ansible **et** boto3 au même endroit). Le chemin du **plugin SSM** est résolu
> dynamiquement (`command -v session-manager-plugin`) → portable Apple Silicon **et** Intel.

### Configuration (pas des installs, mais obligatoires)
- **Identifiants AWS** : profil AWS de votre choix dans `~/.aws/config` + `~/.aws/credentials`,
  région `eu-west-3`. `export AWS_PROFILE=<votre-profil>`.
- **Bucket d'état Terraform** : un bucket S3 existant, passé à l'init. `export TF_STATE_BUCKET=<bucket>`.
- **Mot de passe des utilisateurs de démo** : jamais versionné. `export AD_DEMO_PASSWORD='<mot-de-passe>'`
  (complexité AD : majuscule, minuscule, chiffre, caractère spécial).
- Les variables d'env macOS (`OBJC_DISABLE_INITIALIZE_FORK_SAFETY`, `no_proxy`) sont **exportées
  par les scripts** — rien à faire.

Le preflight de `deploy-all.sh` **vérifie tout ça** et s'arrête en listant précisément ce qui manque.

## 2. Déployer (from scratch)

```bash
export AWS_PROFILE=<votre-profil>
export TF_STATE_BUCKET=<bucket>
export AD_DEMO_PASSWORD='<mot-de-passe>'
./deploy-all.sh
```

Séquence (avec attentes SSM automatiques) :
`terraform apply` → promotion DC `ymmo.lan` → OU/groupes/users → jonction des 2 postes (+ droit RDP)
→ serveur de fichiers (jonction + rename `FILESRV` + partages/ACL) → passerelle IPSec strongSwan
(+ profil `.mobileconfig`).

⏱️ Compter ~20–25 min depuis zéro (surtout la promotion du DC + ses reboots).

## 3. Détruire

```bash
terraform -chdir=terraform/environments/demo destroy
```

> Le coût revient quasi à 0 (cf. [`docs/notes/estimation-couts.md`](../docs/notes/estimation-couts.md)). Modèle **éphémère** assumé.

## 4. À savoir après une recréation

- Le **profil VPN** (`ansible/generated/ymmo-vpn.mobileconfig`) est **régénéré** avec la **nouvelle
  EIP** → le **réinstaller** sur le Mac client (l'ancien pointe sur l'ancienne IP).
- Le **mot de passe AD** et le **secret EAP** sont régénérés : `terraform output -raw ad_admin_password`
  / `-raw vpn_eap_password`.
- Les **service-linked roles** (TGW, Network Firewall) sont au niveau **compte** : ils survivent au
  `destroy` et n'ont pas à être recréés.
- **Network Firewall** : créé par Terraform ; le **câblage du routage egress** (réorientation
  public → endpoint pare-feu) reste à appliquer.

## 5. Connexion aux machines

Voir **`CONNEXION.md`** à la racine du projet (DC, postes, serveur de fichiers, VPN nomade).
