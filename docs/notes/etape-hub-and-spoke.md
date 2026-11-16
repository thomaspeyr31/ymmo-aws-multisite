# Étape dédiée — Interconnexion hub-and-spoke (Transit Gateway)

> Étape pédagogique de la **Phase 3** du déploiement (`plan.fil-rouge.md`).
> Objectif : expliquer **brique par brique** comment le pattern hub-and-spoke se
> traduit sur AWS, **quels flux** sont ouverts entre les agences et le siège **dans
> les deux sens**, et **où** chaque réglage se fait (siège vs agence).
> Schéma associé : `schemas/02-hub-and-spoke-transit-gateway.(drawio|png)`.

---

## 0. Qu'est-ce qu'une architecture « hub-and-spoke » ?

**Hub-and-spoke** (littéralement « moyeu et rayons », comme une roue de vélo) désigne une
**topologie en étoile** : un point central — le **hub** — par lequel transite **tout** le
trafic, et des branches — les **spokes** — qui ne communiquent **qu'à travers** le hub,
jamais directement entre elles.

C'est un **terme standard**, employé tel quel (non traduit) :
- en **réseaux / télécoms** (par opposition au *full mesh* / maillage complet et au
  point-à-point) ;
- en **aérien et logistique**, son domaine d'origine (les compagnies concentrent les vols
  sur un *hub* qui redistribue vers les *spokes*) ;
- dans la **documentation officielle AWS** et le *Well-Architected Framework*, précisément
  autour d'**AWS Transit Gateway**, présenté comme le service pour bâtir une architecture
  hub-and-spoke (le TGW = hub, les VPC = spokes).
- Synonyme français : *topologie en étoile*. Opposés : *full mesh*, *point-à-point*.

**Dans le projet Ymmo** : le **hub = le siège** (Aix-en-Provence) via un **Transit Gateway**,
les **spokes = les agences** (Marseille, Nîmes). On le choisit parce qu'il est :
- **scalable** : passer à 12 agences = 12 spokes branchés sur un seul hub, **sans** maillage
  (un *full mesh* à 12 sites demanderait 66 liaisons : N×(N-1)/2) ;
- **segmenté par nature** : une agence ne voit que le siège (cf. §2) ;
- **centralisé pour la sécurité** : un seul point d'inspection/filtrage au siège.

---

## 1. Les 2 couches du problème (à ne pas confondre)

Relier les sites se joue sur **deux couches distinctes** — c'est le point pédagogique clé :

| Couche | Question à laquelle elle répond | Service AWS | Où elle vit |
|--------|--------------------------------|-------------|-------------|
| **Routage** | « Le paquet *peut-il atteindre* l'autre site ? » | **Transit Gateway** + route tables | TGW (région) + route tables de subnet |
| **Filtrage** | « Le paquet, une fois arrivé, *a-t-il le droit* d'ouvrir ce port ? » | **Security Groups** / **NACL** / Network Firewall | Surtout au **siège**, avec incidences en **agence** |

On configure d'abord le **routage** (sinon rien ne se parle), puis on **ouvre les flux** au plus juste (least-privilege).

---

## 2. Couche routage — le hub-and-spoke proprement dit

Détaillé dans le schéma 02. Résumé des composants :

| # | Composant | Rôle |
|---|-----------|------|
| 1 | **Transit Gateway** | Le hub : routeur régional managé |
| 2 | **3 attachments** | 1 rattachement par VPC (siège, Marseille, Nîmes) |
| 3 | **`rt-hub`** (route table TGW) | Associée au siège → connaît les 3 CIDR (le hub voit tout) |
| 4 | **`rt-spokes`** (route table TGW) | Associée aux agences → ne connaît **que** `10.10/16` (siège) |
| 5 | **Route tables de subnet** | Dans chaque VPC : `CIDR distant → tgw` |

➡️ La segmentation **agence ↔ agence interdit** est obtenue **uniquement par le routage**
(`rt-spokes` n'a aucune route vers l'autre agence). Aucun pare-feu requis pour ça.

---

## 3. Couche flux — quels ports sont ouverts, dans quel sens

Le trafic utile vient d'un **poste d'agence joint au domaine** `ymmo.lan` qui doit
parler aux **serveurs du siège** (contrôleurs AD + serveur de fichiers). Le trafic est
**très asymétrique**.

### 3.1 — Sens AGENCE → SIÈGE (le gros du trafic : join, auth, GPO, fichiers)

| # | Service | Port(s) | Proto | À quoi ça sert |
|---|---------|---------|-------|----------------|
| 1 | DNS | 53 | UDP/TCP | Résoudre `ymmo.lan` (sans ça, **rien** ne marche) |
| 2 | Kerberos | 88 | UDP/TCP | Authentification du poste et de l'utilisateur |
| 3 | Kerberos (chgt mdp) | 464 | UDP/TCP | Changement de mot de passe |
| 4 | LDAP | 389 | UDP/TCP | Requêtes annuaire |
| 5 | LDAPS | 636 | TCP | Annuaire chiffré |
| 6 | Global Catalog | 3268 / 3269 | TCP | Catalogue global (forêt) |
| 7 | SMB | 445 | TCP | Partages de fichiers + **SYSVOL/GPO** |
| 8 | RPC endpoint mapper | 135 | TCP | Point d'entrée RPC |
| 9 | RPC dynamiques | 49152–65535 | TCP | Ports RPC négociés par AD |
| 10 | NTP | 123 | UDP | Synchro horloge — **indispensable** à Kerberos |
| 11 | ICMP (echo) | — | ICMP | Diagnostic (ping siège) — optionnel |

> ⚠️ La **GPO n'ouvre aucun flux entrant en agence** : le poste **tire** (pull) ses
> stratégies via LDAP (#4) + SMB/SYSVOL (#7). Tout reste dans le sens agence→siège.

### 3.2 — Sens SIÈGE → AGENCE (volontairement minimal)

| # | Service | Port(s) | Proto | À quoi ça sert | Nécessaire ? |
|---|---------|---------|-------|----------------|--------------|
| 1 | RDP | 3389 | TCP | Admin/support d'un poste agence depuis l'EC2 admin siège | Optionnel |
| 2 | ICMP (echo) | — | ICMP | Diagnostic (ping agence depuis le siège) | Optionnel |

> Il n'y a **aucune réplication AD entrante** vers les agences : **pas de contrôleur de
> domaine en agence** (les DC sont les Managed AD du siège, multi-AZ). Le patching/SSM
> part en **sortant** du poste agence → **aucune règle entrante** à prévoir pour ça.

**Conclusion de la matrice** : ~10 flux dans le sens agence→siège, **0 à 2** dans l'autre
sens. Le hub-and-spoke est, côté sécurité, **fortement orienté vers le siège**.

---

## 4. OÙ se configure quoi — siège (principal) vs agence (incidences)

C'est le second point pédagogique : **l'essentiel se règle dans le VPC du siège**, mais
**3 réglages côté agence sont non négociables**, sinon la jonction au domaine échoue.

### 4.1 — Au SIÈGE (là où vit 90 % de la conf)

| # | Objet | Réglage |
|---|-------|---------|
| 1 | **SG des serveurs AD / fichiers** | Règles **INBOUND** autorisant comme **source** les CIDR des subnets postes agences (`10.21.20.0/24`, `10.22.20.0/24`) sur les ports du §3.1 |
| 2 | **SG du Managed AD** (géré par AWS) | Y ajouter les mêmes autorisations entrantes |
| 3 | **NACL du subnet serveurs** | Autoriser ces ports **+ retours éphémères** (NACL = stateless) |
| 4 | **Network Firewall** (si inspection inter-VPC) | Règles `allow` sur ces ports pour le trafic agence→siège |

### 4.2 — En AGENCE (les 3 incidences obligatoires)

| # | Objet | Réglage | Si on l'oublie… |
|---|-------|---------|-----------------|
| 1 | **DHCP options set du VPC agence** | Pointer le **DNS** vers les IP des DC Managed AD (résolveur `ymmo.lan`) | La résolution `ymmo.lan` échoue → **join impossible** |
| 2 | **SG des postes agence** | **OUTBOUND** vers le CIDR serveurs siège (`10.10.10.0/24`) sur les ports du §3.1 (souvent couvert par l'egress par défaut) | Le poste ne peut pas initier les flux |
| 3 | **NACL du subnet postes** | Autoriser les **retours éphémères** entrants (réponses du siège) | Connexions à sens unique, time-outs |
| (4) | **Route table subnet** | `10.10.0.0/16 → tgw` (déjà posé en couche routage) | Aucun chemin vers le siège |
| (5) | **NTP / horloge** | Synchro sur les DC (via DHCP/Managed AD) | Dérive d'horloge → **Kerberos casse** |

> 💡 Formulation pour l'oral : « *On ouvre les portes côté serveur (siège), mais chaque
> agence doit savoir à qui parler (DNS) et avoir le droit de sortir (egress + retours).* »

---

## 5. Découpage Terraform de l'étape

| Sous-étape | Ressources Terraform |
|------------|----------------------|
| 5.1 TGW | `aws_ec2_transit_gateway` |
| 5.2 Attachments | `aws_ec2_transit_gateway_vpc_attachment` ×3 |
| 5.3 Route tables TGW | `aws_ec2_transit_gateway_route_table` ×2 (`rt-hub`, `rt-spokes`) + associations + propagations |
| 5.4 Routes VPC | `aws_route` (CIDR distants → TGW) dans chaque route table de subnet |
| 5.5 Flux siège | `aws_security_group_rule` ingress sur SG serveurs + ajustement NACL |
| 5.6 Incidences agence | DNS via `aws_vpc_dhcp_options` + `aws_security_group_rule` egress + NACL |

---

## 6. Validation / démo (preuve que ça marche)

1. Un poste d'agence (Marseille) **joint `ymmo.lan`** à travers le TGW → preuve routage + flux + DNS OK.
2. `ping` siège ↔ agence **OK** ; `ping` Marseille → Nîmes **KO** (segmentation #4).
3. Une **GPO de test** appliquée au poste agence (pull SYSVOL via TGW).
4. Accès à un **partage de fichiers** du siège depuis l'agence (SMB 445).

---

## 7. Validation DÉPLOYÉE — test de segmentation (preuve par les routes)

TGW `tgw-058ec586744462845` déployé avec ses 2 tables. Routes effectivement **apprises** :

| Table TGW | Associée à | Routes apprises (propagées) | Conséquence |
|-----------|-----------|------------------------------|-------------|
| **rt-hub** (`tgw-rtb-065479c2f43a262ac`) | siège | `10.10/16` · `10.21/16` · `10.22/16` | le siège **atteint les 3 sites** |
| **rt-spokes** (`tgw-rtb-0b1e475b651ebcb0a`) | Marseille + Nîmes | `10.10/16` **uniquement** | une agence **ne route QUE vers le siège** |

**Lecture route par route :**
- **Côté TGW** — la *propagation* injecte le CIDR d'un VPC dans une table. `rt-hub` reçoit la
  propagation des **3** attachments → 3 routes. `rt-spokes` ne reçoit **que** celle du siège → 1 route.
  Donc `rt-spokes` n'a **aucune** route vers `10.22/16` (Nîmes) ni `10.21/16` (Marseille) :
  **Marseille ↛ Nîmes**. L'isolation agence↔agence est garantie **par le routage**, pas par un pare-feu.
- **Côté VPC** — `aws_route` ajoute, dans la route table privée de chaque VPC, la route vers le(s)
  CIDR distant(s) **via le TGW** (siège → `10.21`/`10.22` ; chaque agence → `10.10`).

> **⚠️ État actuel : TOUS LES FLUX PASSENT.** Entre siège et agence, sur les chemins autorisés
> (routage + ports ouverts par les Security Groups), le trafic circule **librement et sans
> inspection de contenu**. Les seules barrières en place :
> 1. le **routage** (segmentation — qui peut atteindre qui) ;
> 2. les **Security Groups** (quels ports — on n'a ouvert que les ports AD sur le DC).
> Il n'y a **aucune inspection L7** (pas de pare-feu applicatif) à ce stade.

## 8. Faut-il vraiment un pare-feu (step 4) ? — la bonne question

Puisque tout passe et que tout est **intra-AWS**, on peut légitimement demander : **où est le
risque qui justifierait un Network Firewall ?**

**En vase clos (100 % intra-AWS — ce qu'on a aujourd'hui) :**
- Le trafic ne touche **jamais Internet** (backbone privé AWS).
- Les serveurs n'ont **pas d'IP publique** ; l'accès admin passe par **SSM** (identités IAM).
- La **segmentation** agence↔agence est déjà assurée par le **TGW**.
- → Dans ce périmètre fermé, un pare-feu apporte surtout de la **défense en profondeur** (inspection
  L7, détection d'exfiltration/malware, filtrage de domaines en sortie). **Utile, mais pas vital**
  tant que rien n'entre ni ne sort.

**Le vrai déclencheur = l'ouverture vers l'EXTÉRIEUR.** Dès qu'il faut :
- faire entrer un **poste nomade** (télétravail) ou une **agence on-premise**,
- ou donner une **sortie Internet** aux postes,

…le périmètre s'étend au **réseau public**, et là :
- **IPSec** devient **nécessaire** pour faire entrer ces accès **chiffrés** : **Site-to-Site VPN**
  (agence on-prem) ou **Client VPN** (poste nomade). → c'est l'**option IPSec du step 4**.
- **AWS Network Firewall** prend **tout son sens** : inspecter ce qui franchit la **frontière**
  (entrant/sortant), pas le trafic interne déjà segmenté.

> **Conclusion (à défendre au jury)** : la sécurité du **step 4 (Network Firewall + IPSec)** n'est
> pas un gadget — elle est **dimensionnée par l'ouverture vers l'extérieur**. En intra-AWS pur, c'est
> de la défense en profondeur (recommandée) ; **dès qu'un accès externe existe (poste nomade, agence
> on-prem), elle devient indispensable** — et c'est exactement ce que le sujet anticipe avec « VPN/IPSec ».

## Récap (1 phrase)

Le hub-and-spoke = **routage TGW** (qui peut atteindre qui) **+ flux SG/NACL** (quels ports),
avec l'**ouverture entrante concentrée au siège** et **trois incidences imposées à chaque
agence** : DNS vers l'AD, egress autorisé, retours éphémères.
