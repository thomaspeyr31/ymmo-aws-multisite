# `steps/` — un répertoire par étape du projet

Chaque **étape** (step) du déploiement Ymmo donne lieu à un répertoire
`steps/<NN-nom-du-step>/` qui regroupe sa documentation livrable et le support de
présentation. Les numéros `NN` suivent les phases de `plan.fil-rouge.md`.

## Arborescence d'un step

```
steps/
└── 03-interconnexion-hub-and-spoke/
    ├── schema/                 # schémas SPÉCIFIQUES à ce step (.drawio + .png)
    │   └── hub-and-spoke-transit-gateway.drawio (+ .png)
    ├── documentation.docx      # doc Word livrable (GÉNÉRÉ)
    └── presentation.pptx       # support de la présentation finale (GÉNÉRÉ)
```

- Les schémas **transverses** (ex. architecture cible globale) restent dans
  `./schemas/` à la racine ; seuls les schémas **propres au step** vont dans
  `steps/<step>/schema/`.
- `documentation.docx` et `presentation.pptx` **incluent** les schémas du step.

### Schéma de synthèse obligatoire — `etat-deploye-<sujet>` (CONVENTION)

**Chaque step DOIT fournir un schéma de synthèse « état déployé »** nommé
`schema/etat-deploye-<sujet>.drawio` (+ `.png`) : **une seule vue** qui rassemble tout ce
que le step a mis en place (ressources, flux, segmentation…), à l'image de
`01-reseau/schema/etat-deploye-reseau`, `02-compute-directory/schema/etat-deploye-ad` et
`03-interconnexion-hub-and-spoke/schema/etat-deploye-interconnexion`. Les autres schémas du
step (concept, validation, détail) restent les bienvenus **en plus** de cette vue de synthèse.
Le YAML du step référence ce schéma dans une section finale « Vue d'ensemble — état déployé »
(doc) et une slide de clôture « État déployé — vue d'ensemble » (pptx).

## Chaîne de génération (règles projet)

Le contenu n'est **jamais** écrit en dur dans le Python. Pour chaque step :

1. **Données** → `.generator/steps/<step>.yaml` (source de vérité du contenu).
2. **Style** → `.generator/templates/step-template.docx` et `…-template.pptx`
   (éditables dans Word/PowerPoint ; aucun style dans le Python).
3. **Générateurs** → `.generator/gen_step_docx.py` et `gen_step_pptx.py`
   (template + YAML → fichiers, sans données ni style en dur).

### Régénérer un step

```bash
# 1) éditer le YAML du step (contenu)
$EDITOR .generator/steps/03-interconnexion-hub-and-spoke.yaml
# 2) régénérer docx + pptx
.generator/build_step.sh 03-interconnexion-hub-and-spoke
```

> Pré-requis : venv créé (`python3 -m venv .venv && .venv/bin/pip install -r .generator/requirements.txt`).
> Recréer les templates de zéro (rare) : `.venv/bin/python .generator/bootstrap_templates.py`.

## Créer un nouveau step

1. `mkdir -p steps/<NN-nom>/schema`
2. Y déposer les schémas drawio du step (+ export `.png`), **dont le schéma de synthèse
   obligatoire** `etat-deploye-<sujet>.drawio` (voir convention ci-dessus).
3. Copier un YAML existant vers `.generator/steps/<NN-nom>.yaml` et l'adapter — **ne pas
   oublier** la section finale « Vue d'ensemble — état déployé » + la slide de clôture.
4. `.generator/build_step.sh <NN-nom>`.
