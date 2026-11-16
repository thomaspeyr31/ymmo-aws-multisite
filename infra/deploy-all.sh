#!/usr/bin/env bash
# =====================================================================
# Orchestrateur « from scratch » de l'infra Ymmo — répétable.
#   destroy -> deploy-all.sh  reconstruit TOUT (infra + AD + jonctions + partages + VPN).
# Aucun ID en dur : tout est retrouvé par tag / terraform output.
# Prérequis : voir infra/README.md (le preflight ci-dessous les vérifie).
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"                       # -> infra/
TF_DIR="terraform/environments/demo"
ANS_DIR="ansible"
REGION="eu-west-3"

export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES   # stabilité Ansible/macOS
export no_proxy='*'
export AWS_REGION="$REGION"

# --------------------------------------------------------------------
# 0. PREFLIGHT — dépendances + auth (s'arrête net si quelque chose manque)
# --------------------------------------------------------------------
echo "== [0/6] Preflight dépendances =="
fail=0
need() { command -v "$1" >/dev/null 2>&1 || { echo "  ✗ manque: $1  ($2)"; fail=1; }; }
need terraform               "brew install terraform"
need aws                     "brew install awscli"
need ansible                 "brew install ansible"
need ansible-playbook        "brew install ansible"
need ansible-galaxy          "brew install ansible"
need session-manager-plugin  "brew install --cask session-manager-plugin"
python3 -c 'import boto3, botocore' 2>/dev/null \
  || { echo "  ✗ manque: boto3/botocore  (python3 -m pip install boto3 botocore)"; fail=1; }
aws sts get-caller-identity >/dev/null 2>&1 \
  || { echo "  ✗ AWS non authentifié  (export AWS_PROFILE=<votre-profil> ; aws configure)"; fail=1; }
[ -n "${TF_STATE_BUCKET:-}" ] \
  || { echo "  ✗ TF_STATE_BUCKET non défini  (export TF_STATE_BUCKET=… : bucket S3 de l'état Terraform)"; fail=1; }
[ -n "${AD_DEMO_PASSWORD:-}" ] \
  || { echo "  ✗ AD_DEMO_PASSWORD non défini  (export AD_DEMO_PASSWORD='…' : mot de passe des utilisateurs de démo)"; fail=1; }
[ "$fail" = 0 ] || { echo "Preflight KO — corrige les points ci-dessus puis relance."; exit 1; }
echo "  ✓ toutes les dépendances présentes"

echo "== Collections Ansible (install si absentes) =="
( cd "$ANS_DIR" && ansible-galaxy collection install -r requirements.yml >/dev/null )

# --------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------
# wait_ssm <Role> <count_attendu> <label> : attend que N instances du tag soient SSM Online
wait_ssm() {
  local role="$1" want="$2" label="$3"
  echo "== Attente SSM : $label (cible $want) =="
  for _ in $(seq 1 60); do
    local ids csv n
    ids="$(aws ec2 describe-instances --filters "Name=tag:Role,Values=$role" \
            "Name=instance-state-name,Values=running" \
            --query 'Reservations[].Instances[].InstanceId' --output text)"
    csv="$(echo "$ids" | tr ' \t\n' ',,,' | sed 's/,\{1,\}/,/g; s/^,//; s/,$//')"
    if [ -n "$csv" ]; then
      n="$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$csv" \
            --query 'length(InstanceInformationList[?PingStatus==`Online`])' --output text 2>/dev/null || echo 0)"
      echo "  [$(date +%H:%M:%S)] $label online: ${n:-0}/$want"
      [ "${n:-0}" -ge "$want" ] && return 0
    else
      echo "  [$(date +%H:%M:%S)] $label : pas encore d'instance..."
    fi
    sleep 20
  done
  echo "Timeout SSM ($label)"; return 1
}

ans()  { ( cd "$ANS_DIR" && ansible          -i inventory/aws_ec2.yml "$@" ); }
play() { ( cd "$ANS_DIR" && ansible-playbook -i inventory/aws_ec2.yml "$@" ); }

# Attend que l'AD soit réellement prêt (le DC reboote pendant la promotion)
wait_ad_ready() {
  echo "== Promotion en cours (reboot du DC) — attente de ymmo.lan =="
  sleep 60                                  # laisse le reboot démarrer
  for _ in $(seq 1 40); do
    if ans dc -m ansible.windows.win_shell -a "(Get-ADDomain -ErrorAction Stop).DNSRoot" >/dev/null 2>&1; then
      echo "  -> AD ymmo.lan prêt"; return 0
    fi
    echo "  [$(date +%H:%M:%S)] AD pas encore prêt (DC en reboot)..."; sleep 30
  done
  echo "Timeout : AD non prêt"; return 1
}

# --------------------------------------------------------------------
# 1. TERRAFORM — toute l'infra (idempotent)
# --------------------------------------------------------------------
echo "== [1/6] terraform apply =="
terraform -chdir="$TF_DIR" init -input=false -backend-config="bucket=$TF_STATE_BUCKET" >/dev/null
terraform -chdir="$TF_DIR" apply -auto-approve
PW="$(terraform -chdir="$TF_DIR" output -raw ad_admin_password)"

# --------------------------------------------------------------------
# 2. CONTRÔLEUR DE DOMAINE — promotion + objets AD
# --------------------------------------------------------------------
echo "== [2/6] Contrôleur de domaine =="
wait_ssm domain-controller 1 "DC"
play playbooks/promote-dc.yml -e ad_admin_password="$PW"
wait_ad_ready
play playbooks/ad-objects.yml -e ad_admin_password="$PW"

# --------------------------------------------------------------------
# 3. POSTES D'AGENCE — jonction + droit RDP
# --------------------------------------------------------------------
echo "== [3/6] Postes d'agence =="
wait_ssm poste-agence 2 "postes"
"$ANS_DIR/join-postes.sh"
play playbooks/poste-rdp-access.yml

# --------------------------------------------------------------------
# 4. SERVEUR DE FICHIERS — jonction + rename + partages/ACL
# --------------------------------------------------------------------
echo "== [4/6] Serveur de fichiers =="
wait_ssm fileserver 1 "fileserver"
"$ANS_DIR/fileserver.sh"

# --------------------------------------------------------------------
# 5. PASSERELLE IPSEC — strongSwan + profil macOS
# --------------------------------------------------------------------
echo "== [5/6] Passerelle IPSec nomade =="
wait_ssm vpn-gateway 1 "vpn-gateway"
play playbooks/configure-vpn.yml \
  -e vpn_public_ip="$(terraform -chdir="$TF_DIR" output -json vpn_gateway | python3 -c 'import sys,json;print(json.load(sys.stdin)["public_ip"])')" \
  -e vpn_eap_user="$(terraform -chdir="$TF_DIR" output -json vpn_gateway | python3 -c 'import sys,json;print(json.load(sys.stdin)["eap_user"])')" \
  -e vpn_eap_password="$(terraform -chdir="$TF_DIR" output -raw vpn_eap_password)"

# --------------------------------------------------------------------
# 6. RÉCAP
# --------------------------------------------------------------------
echo "== [6/6] Terminé =="
echo "Infra reconstruite. Rappels :"
echo "  - mot de passe AD : terraform -chdir=$TF_DIR output -raw ad_admin_password"
echo "  - IP passerelle VPN : terraform -chdir=$TF_DIR output -json vpn_gateway"
echo "  - profil VPN régénéré : infra/ansible/generated/ymmo-vpn.mobileconfig"
echo "    (NOUVELLE EIP à chaque recréation -> RÉINSTALLER le profil sur le Mac client)"
echo "  - Network Firewall : créé par terraform, le câblage du routage egress reste à appliquer (cf. TODO)."
