# Step 03 — Postes de travail d'agence (démo de jonction au domaine).
# 1 poste Windows GÉNÉRIQUE par agence (Marseille, Nîmes), dans le tier "postes".
# Le poste joint ymmo.lan comme RESSOURCE PARTAGÉE (non nominatif) : l'utilisateur
# s'identifie au login (cf. docs/notes/note-poste-vs-utilisateur-ad.md).
# Pas d'IP publique, pas de RDP ouvert : accès bureau via SSM Fleet Manager.
# Le DC (10.10.10.10) est joignable via le Transit Gateway (step 03).

locals {
  agences = { for k, v in var.sites : k => v if k != "siege" }
}

# --- Un SG par VPC d'agence : sortant uniquement (SSM via NAT + AD via TGW) ---
resource "aws_security_group" "poste" {
  for_each    = local.agences
  name        = "ymmo-poste-${each.key}"
  description = "Poste agence ${each.key} - sortant uniquement (SSM + AD)"
  vpc_id      = module.network[each.key].vpc_id

  egress {
    description = "Tout sortant (SSM endpoints via NAT + AD vers le siege via TGW)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-ymmo-poste-${each.key}" }
}

resource "aws_instance" "poste" {
  for_each               = local.agences
  ami                    = data.aws_ssm_parameter.win2022_fr.value
  instance_type          = "t3.large" # 2 vCPU / 8 Gio - confort session bureau (Fleet Manager RDP)
  subnet_id              = module.network[each.key].subnets_by_tier["postes"][0]
  iam_instance_profile   = aws_iam_instance_profile.admin.name
  vpc_security_group_ids = [aws_security_group.poste[each.key].id]

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  tags = {
    Name = "ec2-poste-${each.key}"
    Site = each.key
    Role = "poste-agence"
  }
}
