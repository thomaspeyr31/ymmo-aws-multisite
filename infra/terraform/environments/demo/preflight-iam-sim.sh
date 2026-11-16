#!/usr/bin/env bash
# Preflight IAM (variante SIMULATE) — pour les actions SANS dry-run (ds:, iam:, ssm:).
# Utilise `aws iam simulate-principal-policy` AVEC les clés de contexte indispensables :
#   - aws:RequestedRegion (les policies du rôle de déploiement sont conditionnées à eu-west-3)
#   - ec2:InstanceType    (RunInstances est conditionné aux types t3.nano/micro/medium)
# Sans ces contextes, la simulation renvoie de FAUX refus.
#
# Usage : ./preflight-iam-sim.sh preflight/directory.actions
set -euo pipefail

ACTIONS_FILE="${1:?usage: preflight-iam-sim.sh <fichier.actions>}"
[ -f "$ACTIONS_FILE" ] || { echo "Fichier introuvable : $ACTIONS_FILE" >&2; exit 2; }
REGION="${PREFLIGHT_REGION:-eu-west-3}"
ITYPE="${PREFLIGHT_INSTANCE_TYPE:-t3.medium}"

ARN="$(aws sts get-caller-identity --query Arn --output text)"
mapfile -t ACTIONS < <(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$ACTIONS_FILE")

echo "Principal : $ARN"
echo "Contexte  : region=$REGION · instance-type=$ITYPE"
echo "Actions   : ${#ACTIONS[@]} (source: $ACTIONS_FILE)"
echo "----------------------------------------------------------------"

RESULT="$(aws iam simulate-principal-policy \
  --policy-source-arn "$ARN" \
  --action-names "${ACTIONS[@]}" \
  --context-entries \
    "ContextKeyName=aws:RequestedRegion,ContextKeyValues=$REGION,ContextKeyType=string" \
    "ContextKeyName=ec2:InstanceType,ContextKeyValues=$ITYPE,ContextKeyType=string" \
  --query "EvaluationResults[].[EvalActionName,EvalDecision]" \
  --output text)"

printf '%s\n' "$RESULT" | awk '{printf "  %-34s %s\n", $1, $2}'

DENIED="$(printf '%s\n' "$RESULT" | awk '$2!="allowed"{print $1}')"
echo "----------------------------------------------------------------"
if [ -n "$DENIED" ]; then
  echo "❌ EARLY-FAIL : $(printf '%s\n' "$DENIED" | grep -c .) action(s) non autorisée(s) :"
  printf '%s\n' "$DENIED" | sed 's/^/   - /'
  echo "→ Élargir les droits du rôle de déploiement, puis relancer."
  exit 1
fi
echo "✅ Toutes les actions sont autorisées — apply step 02 possible."
