#!/usr/bin/env bash
# Déploiement du step réseau (Phase 1) avec EARLY-FAIL IAM obligatoire.
#   1) preflight IAM  → stoppe net si une habilitation manque
#   2) terraform init + validate + plan
#   3) apply UNIQUEMENT si --apply est passé (confirmation interactive de Terraform)
#
# Usage : ./deploy.sh            # preflight + plan (dry, sûr)
#         ./deploy.sh --apply    # preflight + plan + apply
set -euo pipefail
cd "$(dirname "$0")"

ACTIONS="${ACTIONS:-preflight/network.dryrun}"

echo "==> [1/3] Preflight IAM (early-fail)"
./preflight-iam.sh "$ACTIONS"

echo "==> [2/3] Terraform init + validate + plan"
terraform init -input=false -backend-config="bucket=${TF_STATE_BUCKET:?définir TF_STATE_BUCKET}"
terraform validate
terraform plan -input=false -out=tfplan

if [ "${1:-}" = "--apply" ]; then
  echo "==> [3/3] Terraform apply"
  terraform apply -input=false tfplan
else
  echo "==> [3/3] apply ignoré (relancer avec --apply pour déployer)"
fi
