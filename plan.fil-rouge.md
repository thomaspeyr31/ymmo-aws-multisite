# Plan de déploiement — Ymmo (cloud-natif AWS)

Feuille de route macro du déploiement de l'infrastructure, dans l'ordre
**réseau → VM → interconnexion**, avec la suite logique. Chaque phase = une (ou
plusieurs) branche(s)/PR, redécoupée en sous-étapes au fil de l'eau.
Les items `#` renvoient aux exigences du cahier des charges.

## Vue d'ensemble (séquence de déploiement)

| # | Phase | Ce qu'on construit | Branche(s) | Items MAPPING | État |
|---|-------|--------------------|-----------|----------------|------|
| 0 | **Baseline** | Reset cloud-natif, contexte, backend TF, conventions | `chore/cloud-native-baseline` | #5 | ✅ |
| 1 | **Réseau** | 3 VPC isolés + sous-réseaux + sortie Internet | `feat/network` | #4, 5, 8, 9 | ✅ `step1` |
| 2 | **VM / serveurs** | EC2 + annuaire AD dans le siège | `feat/compute`, `feat/directory` | #1, 2, 3, 17 | ✅ `step2` |
| 3 | **Interconnexion** | Transit Gateway → hub-and-spoke + jonction postes | `feat/transit` | #6, 12 | ✅ `step3` |
| 4 | **Habilitations & serveur de fichiers** | Serveur de fichiers au siège + matrice des droits (1 partage par groupe existant) | `feat/fileserver-droits` | #18, 19 | ⬜ |
| 5 | **IPSec & nomadisme + pare-feu** | Accès distant IPSec (Mac, IKEv2) + AWS Network Firewall (inspection frontière) | `feat/ipsec-nomadisme` | #6, 10, 11 | ⬜ |
| 6 | **Backup & supervision** | Sauvegarde + monitoring | `feat/ops` | #13, 14, 15 | ⬜ |
| 7 | **Ancrage DEV + Cloud** | RDS + récit hybride | `feat/data` | #16, 20, 21 | ⬜ |
| 8 | **Démo & livrables** | Docs, schéma, budget, démo VM | `docs/livrables` | livrables slide 7 | ⬜ |

## Détail des 3 premières phases (périmètre immédiat)

### Phase 1 — Réseau (`feat/network`)
Objectif : 3 VPC **isolés et fonctionnels** avant toute interconnexion.
1. Module `network` paramétrable (1 appel par entité).
2. VPC siège `10.10/16` + agences `10.21/16`, `10.22/16`.
3. 3 sous-réseaux par VPC (public / serveurs / postes) sur 2 AZ.
4. IGW + **NAT Gateway** (sortie Internet) + tables de routage intra-VPC.
5. **DHCP options set** (équivalent cloud-natif du DHCP — #8).
6. `environments/demo` qui instancie les 3 VPC + backend + variables.
- ✅ Validation : `terraform apply` crée 3 VPC, une EC2 de test sort sur Internet via NAT.

### Phase 2 — VM / serveurs (`feat/compute` + `feat/directory`)
Objectif : poser les serveurs et l'annuaire **dans le siège** (intra-VPC, sans encore relier les agences).
1. **AWS Managed Microsoft AD** `ymmo.lan` dans le VPC siège (2 subnets/2 AZ).
2. EC2 **admin Windows** (RSAT) jointe au domaine → outil de gestion des GPO.
3. EC2 **clients de démo** (1-2 par site) — au siège elles joignent déjà le domaine.
4. EC2 serveur de fichiers (support de la matrice des droits, plus tard).
- ✅ Validation : la VM admin du siège est jointe à `ymmo.lan`, une GPO de test s'applique.
- ⚠️ Les VM des **agences** ne peuvent pas encore joindre le domaine → débloqué en phase 3.

### Phase 3 — Interconnexion hub-and-spoke (`feat/transit`) — ÉTAPE PÉDAGOGIQUE DÉDIÉE
Objectif : relier les 3 VPC en **hub-and-spoke** (siège = hub), en **détaillant chaque
brique** pour l'oral. Cette phase a son **document dédié** : `docs/notes/etape-hub-and-spoke.md`
(matrice des flux siège↔agence dans les deux sens + où se configure quoi) et son **schéma
centré** : `schemas/02-hub-and-spoke-transit-gateway.(drawio|png)`.

Deux couches à présenter distinctement :
- **Routage** (qui peut atteindre qui) :
  1. **Transit Gateway** + 3 attachments (1 par VPC).
  2. 2 route tables TGW : `rt-hub` (siège, voit les 3 sites) / `rt-spokes` (agences, voient
     **uniquement** le siège) → **agence ↔ agence interdit** par le routage (segmentation #12).
  3. Routes dans chaque VPC vers les CIDR distants via le TGW.
- **Flux** (quels ports, dans quel sens — least-privilege) :
  4. Ouverture des **flux AD agence→siège** (DNS 53, Kerberos 88/464, LDAP 389/636,
     GC 3268/3269, SMB 445, RPC 135 + 49152-65535, NTP 123) — **côté siège** (SG serveurs).
  5. **Incidences côté agence** (obligatoires) : DNS via DHCP options → Managed AD,
     egress des postes, retours éphémères NACL.
  6. Sens **siège→agence** minimal (RDP admin 3389 optionnel ; aucune réplication AD entrante).
  7. Jonction au domaine des **VM des agences** + AD Sites & Services (réplication par site).
- ✅ Validation **démo** : une VM d'agence joint `ymmo.lan` à travers le TGW ; ping siège↔agence OK ;
  agence1 ↛ agence2 ; GPO de test appliquée ; accès partage SMB du siège depuis l'agence.

## Détail des steps 4 et 5 (ex-#4 « Sécurité » scindé)

### Step 4 — Habilitations & serveur de fichiers (`feat/fileserver-droits`)
Objectif : **rendre concrète la matrice des droits** (slide 3) via un serveur de fichiers.
1. **EC2 `ec2-fileserver-siege`** (Windows 2022 FR) dans le subnet serveurs du siège, **jointe à `ymmo.lan`** (Ansible).
2. **Modèle « un partage par groupe »** sur les **5 groupes fonction existants** : un dossier SMB par pôle (`Direction`, `Commercial`, `CommMktg`, `AdminRH`, `IT`), **ACL NTFS = `GRP_<Pôle>`**. Tout scripté (Ansible : `New-SmbShare`, ACL). *(AdminRH couvre le volet gestion/compta — pas de nouveau groupe.)*
- ✅ Validation : `marc.lefevre` (Commercial) accède à `\\fileserver\Commercial`, **refus** sur `\\fileserver\AdminRH` ; un membre AdminRH a l'inverse. Vérifié en session RDP (Fleet Manager).
- Périmètre : pas d'IPSec ni de pare-feu ici (step 5).

### Step 5 — IPSec & nomadisme + pare-feu (`feat/ipsec-nomadisme`)
Objectif : ouvrir un **accès distant chiffré** et **inspecter la frontière**.
1. **Justification IPSec** : inutile pour agence↔siège **intra-AWS** (le TGW chiffre déjà sur le backbone privé). IPSec n'a de sens que pour faire **entrer un accès depuis Internet** → ici le **nomadisme**.
2. **Cas d'usage nomade** : un salarié en télétravail accède à **son partage du serveur de fichiers** depuis son **Mac**, hors réseau entreprise.
3. **Réalisation** : EC2 **passerelle IKEv2/IPSec** (strongSwan) en subnet public du siège (EIP) ; **client VPN natif macOS** (IKEv2) → tunnel → IP interne → accès SMB via le TGW. (Comparaison jury : AWS Client VPN = TLS/OpenVPN, pas IPSec.)
4. **AWS Network Firewall** au siège (pattern hub d'inspection via TGW) : inspecter le trafic qui franchit la **frontière** (entrant nomade / sortie Internet).
- ✅ Validation : le Mac monte le tunnel IPSec, obtient une IP Ymmo, ouvre le partage du file server ; les flux franchissant la frontière passent par le Network Firewall.

## Notes de séquencement
1. **Pourquoi VM avant interconnexion marche** : on monte d'abord l'AD et les serveurs « isolés » au siège (jonction intra-VPC suffisante), puis le TGW étend l'accès aux agences. C'est l'ordre retenu.
2. **Dépendance forte** : la jonction au domaine *des agences* et la réplication AD multi-sites n'ont de sens **qu'après** la phase 3 → certaines sous-tâches de la phase 2 (clients agences) sont volontairement repoussées en phase 3.
3. **« VPN/IPSec » du sujet** (#6) : matérialisé par le TGW en intra-AWS ; le récit Site-to-Site VPN (vraies agences on-prem) ira dans le livrable Cloud (phase 6/7).
