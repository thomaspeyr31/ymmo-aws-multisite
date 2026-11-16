#!/usr/bin/env bash
# Provisionne le serveur de fichiers : jonction au domaine (+rename FILESRV), attente du
# reboot, puis création des partages SMB + ACL par groupe. Idempotent.
set -euo pipefail

cd "$(dirname "$0")"
TF_DIR="../terraform/environments/demo"

export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
export no_proxy='*'

echo "== Mot de passe admin de domaine (terraform output) =="
PW="$(terraform -chdir="$TF_DIR" output -raw ad_admin_password)"

echo "== Jonction du serveur de fichiers (+rename FILESRV) =="
ansible-playbook -i inventory/aws_ec2.yml playbooks/join-fileserver.yml \
  -e ad_admin_password="$PW"

# ID DYNAMIQUE (jamais en dur) : retrouvé par tag APRÈS la jonction → répétable.
FS_ID="$(aws ec2 describe-instances --region eu-west-3 \
  --filters "Name=tag:Role,Values=fileserver" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[0].InstanceId' --output text)"

echo "== Attente du retour SSM après reboot =="
for i in $(seq 1 40); do
  s=$(aws ssm describe-instance-information --region eu-west-3 \
    --filters "Key=InstanceIds,Values=$FS_ID" \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || echo none)
  echo "  [$(date +%H:%M:%S)] fileserver SSM: ${s:-none}"
  [ "$s" = "Online" ] && { echo "  -> revenu en ligne"; break; }
  sleep 30
done
sleep 20   # laisse les services AD/SMB se stabiliser après le reboot

echo "== Création des partages SMB + ACL par groupe =="
ansible-playbook -i inventory/aws_ec2.yml playbooks/fileserver-shares.yml

echo "== Vérification (partages + appartenance au domaine) =="
ansible -i inventory/aws_ec2.yml fileserver -m ansible.windows.win_shell -a \
  '(Get-CimInstance Win32_ComputerSystem | Select Name,PartOfDomain,Domain | Format-List | Out-String); (Get-SmbShare | Where-Object Path -like "C:\Partages\*" | Select Name,Path | Format-Table -Auto | Out-String)'
