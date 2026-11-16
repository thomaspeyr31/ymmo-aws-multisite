# USERS — Annuaire Ymmo (démo)

> **Domaine :** `ymmo.lan` — **NETBIOS :** `YMMO`
> **Mot de passe commun (démo) :** défini au déploiement via la variable d'environnement `AD_DEMO_PASSWORD` (jamais stocké dans le dépôt).
> ⚠️ DÉMO UNIQUEMENT — ne jamais utiliser en production.

---

## Comptes machines / admin

| Compte | Machine | Mot de passe |
|--------|---------|--------------|
| `YMMO\Administrateur` | DC (`ec2-dc-siege`) | généré par Terraform : `terraform output -raw ad_admin_password` |
| `YMMO\Administrateur` | Poste admin (`ec2-admin-siege`) | idem |

---

## Utilisateurs du domaine

| Login | Nom complet | Titre | Groupe fonction | Site | Groupe site |
|-------|-------------|-------|----------------|------|-------------|
| `sophie.martin` | Sophie Martin | Directrice générale | `GRP_Direction` | Siège | `GRP_Site_Siege` |
| `paul.girard` | Paul Girard | Directeur adjoint | `GRP_Direction` | Siège | `GRP_Site_Siege` |
| `camille.roux` | Camille Roux | Chargée de communication | `GRP_CommMktg` | Siège | `GRP_Site_Siege` |
| `thomas.petit` | Thomas Petit | Responsable marketing | `GRP_CommMktg` | Siège | `GRP_Site_Siege` |
| `nadia.hamon` | Nadia Hamon | Responsable RH | `GRP_AdminRH` | Siège | `GRP_Site_Siege` |
| `eric.moreau` | Eric Moreau | Gestionnaire administratif | `GRP_AdminRH` | Siège | `GRP_Site_Siege` |
| `lea.dubois` | Lea Dubois | Administratrice systèmes | `GRP_IT` | Siège | `GRP_Site_Siege` |
| `julie.bernard` | Julie Bernard | Commerciale | `GRP_Commercial` | Marseille | `GRP_Site_Marseille` |
| `hugo.faure` | Hugo Faure | Technicien support | `GRP_IT` | Marseille | `GRP_Site_Marseille` |
| `marc.lefevre` | Marc Lefevre | Commercial | `GRP_Commercial` | Nîmes | `GRP_Site_Nimes` |

**Format de connexion :** `YMMO\<login>` ou `<login>@ymmo.lan`
**Mot de passe :** valeur de `AD_DEMO_PASSWORD` (tous les comptes)

---

## Accès partages SMB (`\\FILESRV\<partage>`)

| Partage | Groupe autorisé | Exemples d'utilisateurs |
|---------|----------------|------------------------|
| `\\FILESRV\Direction` | `GRP_Direction` | sophie.martin, paul.girard |
| `\\FILESRV\Commercial` | `GRP_Commercial` | julie.bernard, marc.lefevre |
| `\\FILESRV\CommMktg` | `GRP_CommMktg` | camille.roux, thomas.petit |
| `\\FILESRV\AdminRH` | `GRP_AdminRH` | nadia.hamon, eric.moreau |
| `\\FILESRV\IT` | `GRP_IT` | lea.dubois, hugo.faure |
