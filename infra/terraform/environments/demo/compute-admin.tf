# Step 02 — EC2 Windows d'administration (RSAT), jointe au domaine via SSM.
# Pas d'IP publique, pas de port RDP : accès au bureau via SSM Fleet Manager.
# AMI Windows Server 2022 FRANÇAISE résolue par SSM (jamais d'ID figé).

data "aws_ssm_parameter" "win2022_fr" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-French-Full-Base"
}

# --- Rôle IAM de l'instance : SSM (Fleet Manager / Session) + jonction au domaine ---
resource "aws_iam_role" "admin" {
  name = "ymmo-ec2-admin"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "ymmo-ec2-admin" }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.admin.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "admin" {
  name = "ymmo-ec2-admin"
  role = aws_iam_role.admin.name
}

# --- Security group : aucune entrée (SSM = sortant), sortie libre ---
resource "aws_security_group" "admin" {
  name        = "ymmo-ec2-admin"
  description = "EC2 admin Windows - sortant uniquement (SSM + AD)"
  vpc_id      = module.network["siege"].vpc_id

  egress {
    description = "Tout sortant (SSM endpoints via NAT + AD intra-VPC)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-ymmo-ec2-admin" }
}

resource "aws_instance" "admin" {
  ami                    = data.aws_ssm_parameter.win2022_fr.value
  instance_type          = "t3.medium" # plafond autorisé au rôle de déploiement (t3.medium)
  subnet_id              = module.network["siege"].subnets_by_tier["serveurs"][0]
  iam_instance_profile   = aws_iam_instance_profile.admin.name
  vpc_security_group_ids = [aws_security_group.admin.id]

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  # Dépend du DC pour que le DHCP (DNS = DC) soit en place avant la jonction Ansible.
  depends_on = [aws_vpc_dhcp_options_association.ad_siege]

  tags = { Name = "ec2-admin-siege", Site = "siege", Role = "ad-admin" }
}
