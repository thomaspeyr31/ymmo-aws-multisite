# Step 05 — Passerelle IPSec nomade (strongSwan, IKEv2 road-warrior).
# EC2 Ubuntu dans le subnet PUBLIC du siège + EIP : un poste nomade (Mac, client IKEv2
# natif) monte un tunnel chiffré et atteint le siège (DC + FILESRV) en masquerade.
# Auth = EAP-MSCHAPv2 (identifiant générique « nomade » + mot de passe généré).
# Accès admin via SSM (pas de SSH ouvert).

data "aws_ssm_parameter" "ubuntu2204" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

locals {
  vpn_eap_user   = "nomade"          # identifiant VPN générique (la porte ; l'AD filtre ensuite l'accès SMB)
  vpn_client_pool = "10.10.50.0/24"  # IP virtuelles distribuées aux nomades (hors subnets existants)
}

resource "random_password" "vpn_eap" {
  length  = 20
  special = false # mot de passe EAP saisi à la main sur le Mac → on évite les caractères spéciaux
}

resource "aws_security_group" "vpn" {
  name        = "ymmo-vpn-gateway"
  description = "Passerelle IPSec nomade - IKE/NAT-T entrant depuis Internet"
  vpc_id      = module.network["siege"].vpc_id

  ingress {
    description = "IKE (negociation IPSec)"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "IPSec NAT-T (ESP encapsule)"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Tout sortant"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-ymmo-vpn-gateway" }
}

resource "aws_instance" "vpn" {
  ami                    = data.aws_ssm_parameter.ubuntu2204.value
  instance_type          = "t3.medium" # type autorisé au rôle de déploiement (strongSwan = léger)
  subnet_id              = module.network["siege"].subnets_by_tier["public"][0]
  iam_instance_profile   = aws_iam_instance_profile.admin.name # AmazonSSMManagedInstanceCore (OK Linux)
  vpc_security_group_ids = [aws_security_group.vpn.id]
  # Pas de source_dest_check=false : avec le masquerade (SNAT vers l'IP de la passerelle),
  # le trafic ressort avec l'IP propre de l'instance → le check par défaut suffit
  # (et ec2:ModifyInstanceAttribute n'est pas accordé au rôle de déploiement).

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  tags = { Name = "ec2-vpn-gateway-siege", Site = "siege", Role = "vpn-gateway" }
}

resource "aws_eip" "vpn" {
  domain   = "vpc"
  instance = aws_instance.vpn.id
  tags     = { Name = "eip-ymmo-vpn-gateway" }
}
