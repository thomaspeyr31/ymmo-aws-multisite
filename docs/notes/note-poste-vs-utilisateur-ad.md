# Note — Ordinateur vs Utilisateur dans Active Directory

> Concept clé soulevé au step 03 (postes d'agence) : un poste de domaine **n'est PAS nominatif**.
> L'ordinateur et l'utilisateur sont **deux objets séparés** de l'annuaire.

## 1. Deux objets distincts
- **L'ORDINATEUR** « joint le domaine » → il devient une **ressource partagée** du domaine
  `ymmo.lan`. Il **n'appartient à personne**.
- **L'UTILISATEUR** se connecte **au moment du login** avec son compte de domaine. Son
  **identité, ses groupes et ses droits sont dans l'AD (central)** — ils **suivent l'utilisateur**
  sur n'importe quel poste du domaine.

## 2. Conséquence : le poste n'est pas nominatif
- N'importe quel utilisateur du domaine peut ouvrir une session sur n'importe quel poste joint.
- Le poste déployé à Marseille (ou Nîmes) **pourra servir à un IT comme à un commercial** :
  c'est **au login** que le profil et les droits de la personne s'appliquent, pas à la machine.
- C'est « le poste de Marseille », pas « le poste de hugo.faure ».

## 3. Où sont stockées les données d'un utilisateur ?
| Donnée | Où | Suit l'utilisateur ? |
|--------|----|----|
| Identité, groupes, droits | **AD (central)** | ✅ partout |
| Profil **local** (bureau, Documents, réglages) | `C:\Users\<login>` du **PC où il s'est connecté** | ❌ local à ce PC |
| Pour que les documents suivent l'utilisateur | **profils itinérants / redirection de dossiers** vers un **partage réseau** | ✅ (config GPO + serveur de fichiers → **step 4**) |

## 4. Rendre un poste « nominatif » / restreindre (optionnel — step 4)
- Une **GPO « Ouvrir une session localement »** (ou l'attribut `logonWorkstations` de l'utilisateur)
  permet d'imposer **qui peut se connecter où**.
- Usage naturel des **groupes SITE** (`GRP_Site_Marseille`, …) : restreindre l'ouverture de session
  sur les postes d'un site aux **utilisateurs de ce site**.
- **Optionnel**, à faire au step 4 (jolie démonstration de la dimension SITE).

## 4 bis. Console vs RDP — un droit d'ouverture de session différent (piège constaté)
- **Session console** (clavier/écran physique) : ouverte à **tout utilisateur du domaine** par défaut
  (droit « Ouvrir une session localement »). C'est le sens « naturel » de la non-nominativité.
- **Session RDP / Bureau à distance** (ce que fait **Fleet Manager → Connexion Bureau à distance**) :
  exige **en plus** l'appartenance au groupe local **« Utilisateurs du Bureau à distance »** du poste.
  Un simple utilisateur du domaine n'y est pas → **RDP refusé même avec le bon mot de passe**.
- Pour la démo (accès via la console AWS = RDP), on a donc ajouté **« Utilisateurs du domaine »** à
  ce groupe local sur les 2 postes (playbook `poste-rdp-access.yml`) → la non-nominativité vaut alors
  aussi pour RDP : n'importe quel compte de domaine ouvre une session sur n'importe quel poste.
- **Step 04** : restreindre par **groupe SITE** (GPO « Ouvrir une session ») = la démonstration
  inverse (limiter qui peut se connecter où).

## 5. Pour la démo (step 03)
- On déploie des **postes génériques** (1 par agence), simplement **joints au domaine**.
- La « nomination » se fait **au login** : session **`hugo.faure`** (IT) sur Marseille,
  **`marc.lefevre`** (Commercial) sur Nîmes.
- **Aucun paramétrage par-utilisateur** sur la machine pour la jonction.

---

### En une phrase
L'ordinateur joint le domaine (ressource partagée) ; l'utilisateur s'identifie **au login** et ses
droits viennent de l'**AD** — le poste de Marseille/Nîmes sert donc indifféremment à un IT ou un
commercial, c'est la session ouverte qui détermine tout.
