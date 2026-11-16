# Step 02 (option C) — Contrôleur de domaine AUTO-GÉRÉ sur EC2 (remplace le Managed AD).
# Windows Server 2022 FR, IP privée fixe, promu DC de la forêt ymmo.lan via Ansible
# (Install-ADDSForest). Le DC est aussi serveur DNS de ymmo.lan.

# Mot de passe du compte Administrateur du domaine + Safe Mode (DSRM), généré.
resource "random_password" "ad_admin" {
  length           = 20
  special          = true
  override_special = "!@#$%^&*()-_=+"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

locals {
  dc_private_ip = "10.10.10.10" # IP fixe dans le subnet serveurs az-a (10.10.10.0/25)
  ad_ports = [
    { p = 53, proto = "tcp" }, { p = 53, proto = "udp" }, # DNS
    { p = 88, proto = "tcp" }, { p = 88, proto = "udp" }, # Kerberos
    { p = 135, proto = "tcp" },                           # RPC endpoint mapper
    { p = 389, proto = "tcp" }, { p = 389, proto = "udp" }, # LDAP
    { p = 445, proto = "tcp" },                           # SMB (SYSVOL/GPO)
    { p = 464, proto = "tcp" }, { p = 464, proto = "udp" }, # Kerberos chgt mdp
    { p = 636, proto = "tcp" },                           # LDAPS
    { p = 3268, proto = "tcp" }, { p = 3269, proto = "tcp" }, # Global Catalog
    { p = 123, proto = "udp" },                           # NTP
  ]
}

resource "aws_security_group" "dc" {
  name        = "ymmo-dc"
  description = "Controleur de domaine - ports AD ouverts aux sites Ymmo"
  vpc_id      = module.network["siege"].vpc_id

  dynamic "ingress" {
    for_each = local.ad_ports
    content {
      description = "AD ${ingress.value.proto}/${ingress.value.p}"
      from_port   = ingress.value.p
      to_port     = ingress.value.p
      protocol    = ingress.value.proto
      cidr_blocks = ["10.0.0.0/8"] # siège + agences (agrégat du plan d'adressage)
    }
  }

  ingress {
    description = "AD RPC dynamiques"
    from_port   = 49152
    to_port     = 65535
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
    description = "Tout sortant"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-ymmo-dc" }
}

resource "aws_instance" "dc" {
  ami                    = data.aws_ssm_parameter.win2022_fr.value
  instance_type          = "t3.medium"
  subnet_id              = module.network["siege"].subnets_by_tier["serveurs"][0]
  private_ip             = local.dc_private_ip
  iam_instance_profile   = aws_iam_instance_profile.admin.name
  vpc_security_group_ids = [aws_security_group.dc.id]

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  tags = { Name = "ec2-dc-siege", Site = "siege", Role = "domain-controller", Backup = "true" }
}
