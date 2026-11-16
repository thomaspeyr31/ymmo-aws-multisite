# CONNEXION — accès aux machines du projet Ymmo

> Référence **globale** des modes opératoires de connexion aux ressources du projet.
> Une section par machine / type de machine. ⚠️ **Aucun secret en clair ici** : les mots de
> passe se récupèrent via Terraform ou un coffre (voir chaque section).

## Conventions générales

- **Région** : `eu-west-3` (Paris). **Profil AWS** : `<votre-profil>`.
  ```bash
  export AWS_PROFILE=<votre-profil> AWS_REGION=eu-west-3
  ```
- Les EC2 sont en **subnet privé, sans IP publique, sans port ouvert** → accès via **AWS SSM**
  (Session Manager / Fleet Manager), jamais en RDP/SSH direct depuis Internet.
- Les **IDs d'instance sont dynamiques** (changent à la recréation) → toujours les retrouver par **tag**.
- **Secrets** : récupérés à la demande (`terraform output -raw <name>`), jamais commités.

## Inventaire (résumé)

| # | Machine | Tag `Role` | OS | Accès | Compte |
|---|---------|-----------|----|----|--------|
| 1 | Contrôleur de domaine | `domain-controller` | Windows 2022 FR | SSM (Fleet Manager / Session Mgr) | `YMMO\Administrateur` |
| 2 | Poste d'administration | `ad-admin` | Windows 2022 FR | SSM | `YMMO\Administrateur` |
| 3 | Poste agence Marseille | `poste-agence` (Site=marseille) | Windows 2022 FR | SSM | session **utilisateur** (ex. `hugo.faure`) |
| 4 | Poste agence Nîmes | `poste-agence` (Site=nimes) | Windows 2022 FR | SSM | session **utilisateur** (ex. `marc.lefevre`) |

---

## 1. Active Directory — DC & poste admin (step 02, Windows)

VM Windows de `ymmo.lan`, gérées par SSM. **Compte admin du domaine** : `YMMO\Administrateur`
(AMI **française** → compte intégré RID-500 = `Administrateur`, pas `Administrator`).

**Récupérer le mot de passe & les IDs :**
```bash
cd infra/terraform/environments/demo
terraform output -raw ad_admin_password          # mot de passe Administrateur (ne pas committer)
# ID du DC / du poste admin (dynamiques) :
aws ec2 describe-instances --region eu-west-3 \
  --filters "Name=tag:Role,Values=domain-controller" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value}" --output text
```

### 1a. Bureau graphique — Fleet Manager Remote Desktop (voir la console AD)
**Pré-requis IAM** : `ssm-guiconnect:*` .
1. Console AWS, région **Paris** → **Systems Manager → Fleet Manager** → instance `ec2-dc-siege`.
2. **Node actions → Connect with Remote Desktop** → auth **User credentials** :
   `Administrateur` + mot de passe (`terraform output -raw ad_admin_password`).
3. Dans le bureau : **« Utilisateurs et ordinateurs Active Directory »** (`dsa.msc`)
   → `ymmo.lan` → OU **Ymmo** → `Sites` (Siege/Marseille/Nimes = users) et `Groupes`.

### 1b. Terminal PowerShell — Session Manager (sans IAM supplémentaire)
**Pré-requis IAM** : `ssm:StartSession` (déjà accordé).
1. **Systems Manager → Session Manager → Start session** → `ec2-dc-siege`.
2. Inspection :
   ```powershell
   Get-ADOrganizationalUnit -Filter * | Select Name, DistinguishedName
   Get-ADGroup -Filter 'Name -like "GRP_*"' | Select Name
   Get-ADUser -Filter * -SearchBase 'OU=Sites,OU=Ymmo,DC=ymmo,DC=lan' | Select Name, SamAccountName
   ```

### 1c. Automatisation — Ansible (aws_ssm)
```bash
cd infra/ansible
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES no_proxy='*' AWS_PROFILE=<votre-profil> AWS_REGION=eu-west-3
PW="$(terraform -chdir=../terraform/environments/demo output -raw ad_admin_password)"
ansible dc -i inventory/aws_ec2.yml -m ansible.windows.win_ping
ansible-playbook -i inventory/aws_ec2.yml playbooks/ad-objects.yml -e ad_admin_password="$PW"
```
- Inventaire **dynamique** (tag `Project=ymmo`, groupes `dc` / `ad_admin`), connexion **SSM**.
- ⚠️ **Jamais deux runs Ansible en parallèle** sur la même VM (conflit de session SSM).

### Pièges connus (AD)
- AMI **française** → `Administrateur` (format down-level `YMMO\Administrateur`).
- Promotion lente sur `t3.medium` → recréer en `t2.large` si besoin.
- Fleet Manager RDP (GUI) exige `ssm-guiconnect:*` ; Session Manager (terminal) non.

---

## 2. Postes d'agence — Marseille & Nîmes (step 03, Windows joints au domaine)

Postes Windows **génériques** (non nominatifs) **joints à `ymmo.lan`** via le Transit Gateway.
Le poste est une **ressource partagée** : l'utilisateur s'identifie **au login**
(cf. `docs/notes/note-poste-vs-utilisateur-ad.md`). Pas d'IP publique, accès **SSM**.

**Retrouver les IDs (dynamiques) :**
```bash
aws ec2 describe-instances --region eu-west-3 \
  --filters "Name=tag:Role,Values=poste-agence" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].{Id:InstanceId,Site:Tags[?Key=='Site']|[0].Value,Ip:PrivateIpAddress}" --output table
# ou : terraform -chdir=infra/terraform/environments/demo output postes_agence
```

### 2a. Ouvrir une session utilisateur — Fleet Manager Remote Desktop
**Pré-requis IAM** : `ssm-guiconnect:*` (idem DC).
**Pré-requis Windows** : Fleet Manager « Bureau à distance » = **session RDP** → l'utilisateur doit
appartenir au groupe local **« Utilisateurs du Bureau à distance »** (Remote Desktop Users) du poste.
On y a ajouté **« Utilisateurs du domaine »** (playbook `poste-rdp-access.yml`) → **tout** compte de
domaine peut ouvrir une session RDP sur **n'importe quel** poste (non-nominativité). *(Sans cette
appartenance, RDP refuse même avec un mot de passe valide — la session **console** physique, elle,
ne l'exige pas. La restriction par SITE viendra au step 04 via GPO « Ouvrir une session ».)*

1. Console AWS Paris → **Systems Manager → Fleet Manager** → `ec2-poste-marseille` (ou `-nimes`).
2. **Node actions → Connect with Remote Desktop** → auth **User credentials** avec un
   **compte de domaine** : `marc.lefevre@ymmo.lan` (ou `YMMO\marc.lefevre`),
   mot de passe AD (`<mot-de-passe-démo>` pour la démo). C'est **la session ouverte** qui détermine
   l'identité/les droits — pas la machine.
3. **Non-nominativité vérifiée** : `marc.lefevre` (Nîmes) ouvre aussi une session sur le poste de
   **Marseille**, et `hugo.faure` (Marseille) sur celui de **Nîmes** — aucun lien poste↔personne.
4. (Au step 04 : la **matrice des droits** + serveur de fichiers, et la GPO de restriction par SITE,
   rendront ces sessions différenciées/restreintes.)

### 2b. Jonction au domaine (automatisation Ansible)
```bash
cd infra/ansible
./join-postes.sh          # DNS poste -> DC (10.10.10.10), Add-Computer ymmo.lan, reboot, vérif
```
- Groupe d'inventaire dynamique **`postes`** (tag `Role=poste-agence`).
- La jonction se fait via **async fire-and-forget** (comme la promotion du DC) pour éviter le
  « worker dead state » SSM/macOS.

### 2c. Visualiser la jonction depuis le DC (console AWS → bureau du DC)
But : **voir les postes apparaître dans l'annuaire** une fois joints.
1. Console AWS Paris → **Systems Manager** → **Explorer les nœuds** (*Fleet Manager*).
2. Sélectionner le nœud **`ec2-dc-siege`** → **Actions du nœud** → **Connexion Bureau à distance**.
3. Auth **User credentials** : `Administrateur` + `terraform output -raw ad_admin_password`.
4. Dans le bureau du DC, ouvrir **« Utilisateurs et ordinateurs Active Directory »** (`dsa.msc`).
5. Déplier **`ymmo.lan`** → conteneur **`Computers`** : les 2 postes joints y figurent
   (`EC2AMAZ-…` pour Marseille et Nîmes). *(Le DC, lui, est sous `Domain Controllers`.)*
   - Ils sont dans **`CN=Computers`** (conteneur par défaut) car la jonction n'a pas précisé d'OU.
     Le rangement par OU de site (`OU=Marseille`/`OU=Nimes`) sera fait au **step 04** (avec les GPO).

**Équivalent en ligne de commande (Session Manager terminal sur le DC) :**
```powershell
Get-ADComputer -Filter * | Select Name, DistinguishedName    # doit lister les 2 EC2AMAZ-…
```

**Tester une ouverture de session utilisateur** (Fleet Manager RDP sur `ec2-poste-nimes`) :
`YMMO\marc.lefevre` / `<mot-de-passe-démo>` — fonctionne **aussi** sur `ec2-poste-marseille`
(compte de domaine, aucune restriction de site tant que la GPO du step 04 n'est pas posée).

### Pièges connus (postes)
- Booter en **AmazonProvidedDNS** (VPC agence) pour que l'agent SSM s'enregistre, **puis**
  pointer la NIC vers le DC au moment de la jonction (le DC forwarde l'externe → SSM reste joignable).
- Vérifier la jonction côté **DC** : `Get-ADComputer -Filter *` doit lister `EC2AMAZ-…` des 2 postes.
- Les postes joints atterrissent dans **`CN=Computers`** (pas dans une OU) faute de `-OUPath` au join.

---

## 3. Accès nomade — VPN IPSec depuis le Mac (step 05)

Tunnel **IKEv2/IPSec** entre un poste hors entreprise (Mac) et le siège, via la passerelle
**strongSwan** (`ec2-vpn-gateway-siege`, EC2 Ubuntu en subnet public + **EIP**). Auth **EAP** (le
client IKEv2 **natif macOS**). Une fois connecté, le nomade atteint le siège (DC, `FILESRV`) comme
au bureau. Config 100 % scriptée (Terraform + Ansible `configure-vpn.yml`).

**Récupérer l'IP publique et les identifiants :**
```bash
TF=infra/terraform/environments/demo
terraform -chdir=$TF output -json vpn_gateway       # public_ip + eap_user (= "nomade")
terraform -chdir=$TF output -raw vpn_eap_password   # mot de passe EAP (ne pas committer)
```

### 3a. Installer le profil sur le Mac (`.mobileconfig`)
Le profil **`infra/ansible/generated/ymmo-vpn.mobileconfig`** (généré par le playbook ; **gitignored**,
contient le mot de passe) embarque **la config VPN + le certificat CA** (pour que macOS fasse
confiance au serveur). **⚠️ il contient le secret EAP → ne pas le partager.**

1. **Double-cliquer** le `.mobileconfig` (Finder). Sur **macOS Tahoe/Sequoia**, ça **n'installe pas**
   directement : ça met le profil **en attente**.
2. **Réglages Système → Général → VPN et gestion des appareils** (ou **Profils**) → le profil
   **« Ymmo VPN nomade »** apparaît en attente → **double-clic → Installer** → mot de passe Mac.
   Il est marqué **« Non vérifié »** (CA auto-signée) : **normal**, on installe quand même.
3. Si rien n'apparaît : ré-ouvrir le fichier puis le panneau Profils via
   `open "x-apple.systempreferences:com.apple.preferences.configurationprofiles"`.

### 3b. Connecter / déconnecter
- **Installé ≠ actif** : aucun trafic ne passe tant qu'on ne se connecte pas (pas de « VPN sur demande »).
- **Connexion** : **Réglages → Réseau → VPN → Ymmo VPN nomade → Connexion** (ou barre des menus /
  Centre de contrôle). **Tunnel complet** : une fois connecté, **tout** le trafic du Mac sort par la
  passerelle (voulu pour l'inspection pare-feu du step 05).
- **Déconnexion** : même endroit → **Déconnexion** (immédiat, pas de reconnexion auto).
- **Retirer entièrement** : Réglages → Général → VPN et gestion des appareils → **Supprimer le profil**.

### 3c. Test (CT-05) une fois connecté
Finder → **Aller → Se connecter au serveur…** (⌘K) → `smb://filesrv.ymmo.lan/Commercial`
→ `YMMO\marc.lefevre` / `<mot-de-passe-démo>` → l'espace s'ouvre ; `…/AdminRH` → **refusé** (NTFS du step 04).

### Pièges connus (VPN nomade)
- **macOS Tahoe/Sequoia** : un `.mobileconfig` **ne s'installe jamais en ligne de commande** (retiré
  par Apple pour les profils non-MDM) ni par simple double-clic → toujours passer par **Réglages →
  Profils** et cliquer **Installer**.
- Le **RemoteID** du profil = l'**IP publique** (EIP) ; elle doit figurer en **SAN** du certificat
  serveur (géré par le playbook). Si l'EIP change (recréation), **régénérer** le profil.
- Profil **« Non vérifié »** = CA auto-signée embarquée → attendu, pas une erreur.

---

<!-- Ajouter ici les sections d'accès pour les futures machines (RDS, etc.) -->
