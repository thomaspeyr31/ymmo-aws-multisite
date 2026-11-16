# Note — DNS de l'Active Directory (zone privée `ymmo.lan`)

> Point structurant du **step 02** (compute + Active Directory). Explique le rôle du DNS
> d'AD, pourquoi il est privé, d'où il vient et comment on y branche les machines.
> Schéma associé : `steps/02-compute-directory/schema/dns-resolution-ad.(drawio|png)`.

---

## 1. DNS = annuaire téléphonique du réseau
Le DNS traduit un **nom** en **adresse IP** (`serveur-fichiers.ymmo.lan` → `10.10.10.5`).
Sans lui, les machines ne se trouvent pas par leur nom.

## 2. Pourquoi Active Directory a besoin de SON propre DNS
AD est **indissociable du DNS**. Pour « joindre le domaine » ou authentifier un utilisateur,
une machine doit d'abord **localiser les contrôleurs de domaine** — elle le fait via une
requête DNS spéciale (enregistrements `SRV` du type « où sont les DC de `ymmo.lan` ? »).
**Pas de DNS qui connaît `ymmo.lan` → pas d'AD.** C'est pourquoi AD embarque toujours un DNS.

## 3. Un DNS PRIVÉ, et d'où il sort
- **Origine** : à la création du **AWS Managed Microsoft AD**, AWS monte 2 contrôleurs de
  domaine (1 par AZ) qui sont **aussi 2 serveurs DNS**. Ils hébergent automatiquement la zone
  `ymmo.lan`. On ne configure rien : la zone naît avec l'annuaire, et on récupère **2 IP de
  DNS privées** (dans les subnets serveurs).
- **Privé** : la zone `ymmo.lan` n'existe **que** dans le réseau AWS. Ce **n'est pas un domaine
  Internet** ; personne à l'extérieur ne peut le résoudre. C'est de la résolution **interne**,
  voulue.

## 4. Comment on y branche les machines (le DHCP options set)
Le **DHCP options set** du VPC distribue à chaque machine l'adresse du serveur DNS à utiliser.
- **État Phase 1 (réseau)** : DHCP = `AmazonProvidedDNS` → `ymmo.lan` est **inrésolvable**.
- **Step 02** : on **repointe le DHCP vers les 2 IP du DNS de l'AD**. Dès lors, chaque machine :
  1. pose ses questions **internes** (`*.ymmo.lan`) au **DNS de l'AD** (réponse directe) ;
  2. ses questions **externes** (`google.com`) sont **forwardées** par le DNS de l'AD vers le
     **Route 53 Resolver** du VPC, puis Internet (via le NAT Gateway).

> **C'est l'étape pivot du step 02** : sans ce repointage DHCP, la jonction de domaine échoue.
> (Côté agences, c'est aussi l'incidence n°1 vue au step 03 — voir `docs/notes/etape-hub-and-spoke.md`.)

## 5. Bonus : auto-enregistrement des noms
Quand une machine **joint le domaine**, elle **enregistre toute seule** son nom dans le DNS
d'AD (`pc-compta-01.ymmo.lan` → son IP). **Aucune entrée DNS à créer à la main.**

## 6. Intérêt — récapitulatif
| # | Intérêt | Détail |
|---|---------|--------|
| 1 | Obligatoire pour AD | Sans DNS `ymmo.lan`, ni jonction ni authentification |
| 2 | Résolution interne automatique | Serveurs/postes trouvés par nom, auto-enregistrés |
| 3 | Source unique de noms | Pas de fichier hosts ni de DNS séparé à maintenir |
| 4 | Multi-sites | Les agences (via TGW, step 03) résolvent le **même** `ymmo.lan` |

## 7. À ne pas confondre
- **DNS de l'AD** (cette note) = zone `ymmo.lan`, résolution de **noms**.
- **OU déléguée** (autre sujet) = dossier de rangement **dans l'annuaire** où AWS te donne les
  droits d'admin pour créer OU/groupes/utilisateurs. Rien à voir avec le DNS.

---

### En une phrase
Le DNS de l'AD est un **DNS privé interne** (`ymmo.lan`), **créé automatiquement avec le Managed
AD**, hébergé par les contrôleurs de domaine ; on y **branche les machines via le DHCP du VPC**.
Il est **indispensable** (l'AD ne marche pas sans), **résout les noms internes tout seul**, et
**forwarde** le reste vers Internet.
