# Step 04 — Serveur de fichiers du siège (matrice des droits par pôle).
# Windows 2022 FR, joint à ymmo.lan, héberge un partage SMB par groupe fonction
# (ACL NTFS = GRP_<Pôle>). Accessible depuis le siège ET les agences via le TGW.
# Pas d'IP publique : accès admin via SSM ; accès partages via SMB 445 intra-10.0.0.0/8.

resource "aws_security_group" "fileserver" {
  name        = "ymmo-fileserver"
  description = "Serveur de fichiers - SMB ouvert au domaine (siege + agences via TGW)"
  vpc_id      = module.network["siege"].vpc_id

  ingress {
    description = "SMB (partages de fichiers) depuis le plan adressage Ymmo 10.0.0.0/8"
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    description = "ICMP (diagnostic)"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description = "Tout sortant (SSM via NAT + AD vers le DC)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-ymmo-fileserver" }
}

resource "aws_instance" "fileserver" {
  ami                    = data.aws_ssm_parameter.win2022_fr.value
  instance_type          = "t3.large"
  subnet_id              = module.network["siege"].subnets_by_tier["serveurs"][0]
  iam_instance_profile   = aws_iam_instance_profile.admin.name
  vpc_security_group_ids = [aws_security_group.fileserver.id]

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  tags = { Name = "ec2-fileserver-siege", Site = "siege", Role = "fileserver", Backup = "true" }
}
