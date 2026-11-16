#!/usr/bin/env bash
# Génère documentation.docx + presentation.pptx d'un step depuis son YAML.
# Usage : .generator/build_step.sh 03-interconnexion-hub-and-spoke
set -euo pipefail

STEP="${1:?usage: build_step.sh <step-id>  (ex: 03-interconnexion-hub-and-spoke)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="$ROOT/.venv/bin/python"
GEN="$ROOT/.generator"
YAML="$GEN/steps/${STEP}.yaml"
OUT="$ROOT/steps/${STEP}"

[ -f "$YAML" ] || { echo "YAML introuvable : $YAML" >&2; exit 1; }

# 1) on (re)génère toujours depuis le YAML — le YAML est la source de vérité
"$PY" "$GEN/gen_step_docx.py" --yaml "$YAML" \
    --template "$GEN/templates/step-template.docx" \
    --out "$OUT/documentation.docx"
"$PY" "$GEN/gen_step_pptx.py" --yaml "$YAML" \
    --template "$GEN/templates/step-template.pptx" \
    --out "$OUT/presentation.pptx"

echo "OK → $OUT/documentation.docx + presentation.pptx"
