#!/usr/bin/env bash
# Preflight IAM — EARLY-FAIL avant tout terraform apply.
# Méthode : DRY-RUN EC2 RÉEL (vérité terrain), pas simulate-principal-policy
# (qui s'est révélé donner des FAUX NÉGATIFS après attachement récent de policy).
#
# Chaque ligne du fichier <step>.dryrun :  <label> :: <sous-commande aws ec2 + args>
# Le script ajoute --dry-run --region. Décision :
#   - stderr contient "UnauthorizedOperation"  -> REFUS (l'IAM bloque)
#   - sinon (DryRunOperation / erreur de params) -> AUTORISÉ (auth franchie)
#
# Usage : ./preflight-iam.sh preflight/network.dryrun
set -euo pipefail

DRYRUN_FILE="${1:?usage: preflight-iam.sh <fichier.dryrun>}"
[ -f "$DRYRUN_FILE" ] || { echo "Fichier introuvable : $DRYRUN_FILE" >&2; exit 2; }
# Région de DÉPLOIEMENT (pas celle du profil CLI) : la policy du rôle de déploiement est
# conditionnée à eu-west-3, donc le dry-run doit s'y exécuter.
REGION="${PREFLIGHT_REGION:-eu-west-3}"

echo "Principal : $(aws sts get-caller-identity --query Arn --output text)"
echo "Région    : $REGION"
echo "Source    : $DRYRUN_FILE"
echo "----------------------------------------------------------------"

DENIED=0
while IFS= read -r line; do
  case "$line" in ''|\#*) continue ;; esac
  label="${line%%::*}"; cmd="${line#*:: }"
  label="$(echo "$label" | xargs)"
  err="$(aws ec2 $cmd --dry-run --region "$REGION" 2>&1 || true)"
  if grep -q "UnauthorizedOperation" <<<"$err"; then
    printf "  %-26s ❌ refusé\n" "$label"; DENIED=$((DENIED+1))
  else
    printf "  %-26s ✅ autorisé\n" "$label"
  fi
done < "$DRYRUN_FILE"

echo "----------------------------------------------------------------"
if [ "$DENIED" -gt 0 ]; then
  echo "❌ EARLY-FAIL : $DENIED action(s) refusée(s) — élargir les droits du rôle de déploiement puis relancer."
  exit 1
fi
echo "✅ Toutes les actions testées sont autorisées — apply possible."
