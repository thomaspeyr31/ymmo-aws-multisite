#!/usr/bin/env bash
# Joint les postes d'agence au domaine ymmo.lan, puis attend leur retour après reboot.
# Idempotent : relançable sans risque (un poste déjà joint = "ok", pas de changement).
set -euo pipefail

cd "$(dirname "$0")"
TF_DIR="../terraform/environments/demo"
# IDs DYNAMIQUES (jamais en dur) : retrouvés par tag → répétable après destroy/apply.
POSTES_IDS="$(aws ec2 describe-instances --region eu-west-3 \
  --filters "Name=tag:Role,Values=poste-agence" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text)"
POSTES_COUNT="$(echo "$POSTES_IDS" | wc -w | tr -d ' ')"

# Stabilité Ansible sur macOS (fork/objc + proxy) — cf. ansible.cfg
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
export no_proxy='*'

echo "== Mot de passe admin de domaine (terraform output) =="
PW="$(terraform -chdir="$TF_DIR" output -raw ad_admin_password)"

echo "== Jonction des postes au domaine ymmo.lan =="
ansible-playbook -i inventory/aws_ec2.yml playbooks/join-postes.yml \
  -e ad_admin_password="$PW"

echo "== Attente du retour SSM après reboot (jonction finalisée) =="
ids_csv="$(echo "$POSTES_IDS" | tr ' \t\n' ',,,' | sed 's/,\{1,\}/,/g; s/^,//; s/,$//')"
for i in $(seq 1 40); do
  n=$(aws ssm describe-instance-information --region eu-west-3 \
    --filters "Key=InstanceIds,Values=$ids_csv" \
    --query 'length(InstanceInformationList[?PingStatus==`Online`])' --output text 2>/dev/null || echo 0)
  echo "  [$(date +%H:%M:%S)] postes Online: ${n:-0}/${POSTES_COUNT}"
  [ "${n:-0}" = "${POSTES_COUNT}" ] && { echo "  -> postes revenus en ligne"; break; }
  sleep 30
done

echo "== Vérification de l'appartenance au domaine (PartOfDomain / Domain) =="
ansible -i inventory/aws_ec2.yml postes -m ansible.windows.win_shell \
  -a '(Get-CimInstance Win32_ComputerSystem | Select-Object Name,PartOfDomain,Domain | Format-List | Out-String)'
