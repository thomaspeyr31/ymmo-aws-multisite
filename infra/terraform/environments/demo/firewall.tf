# Step 05 — AWS Network Firewall (inspection de la frontière, egress du siège).
# Inspecte/journalise le trafic sortant du VPC siège et BLOQUE une liste de domaines
# (démo : *.facebook.com). Pattern egress : le pare-feu s'intercale entre le subnet
# public (NAT/VPN) et l'IGW.

# --- Sous-réseau dédié au endpoint du pare-feu (petit /28, AZ a) ---
resource "aws_subnet" "firewall" {
  vpc_id            = module.network["siege"].vpc_id
  cidr_block        = "10.10.30.0/28"
  availability_zone = var.azs[0]
  tags              = { Name = "subnet-siege-firewall", Site = "siege", Tier = "firewall" }
}

# --- Règle stateful : liste de domaines interdits (DENYLIST sur SNI/HTTP Host) ---
resource "aws_networkfirewall_rule_group" "block_domains" {
  name     = "ymmo-block-domains"
  type     = "STATEFUL"
  capacity = 100

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "DENYLIST"
        target_types         = ["TLS_SNI", "HTTP_HOST"]
        targets              = [".facebook.com", ".tiktok.com"]
      }
    }
  }

  tags = { Name = "ymmo-block-domains" }
}

resource "aws_networkfirewall_firewall_policy" "this" {
  name = "ymmo-egress-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.block_domains.arn
    }
  }

  tags = { Name = "ymmo-egress-policy" }
}

resource "aws_networkfirewall_firewall" "this" {
  name                = "ymmo-egress-firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn
  vpc_id              = module.network["siege"].vpc_id

  subnet_mapping {
    subnet_id = aws_subnet.firewall.id
  }

  tags = { Name = "ymmo-egress-firewall" }
}

# --- Journalisation (CloudWatch) : flux + alertes (domaines bloqués) ---
resource "aws_cloudwatch_log_group" "nfw" {
  name              = "/ymmo/network-firewall"
  retention_in_days = 7
  tags              = { Name = "ymmo-nfw-logs" }
}

resource "aws_networkfirewall_logging_configuration" "this" {
  firewall_arn = aws_networkfirewall_firewall.this.arn
  logging_configuration {
    log_destination_config {
      log_destination      = { logGroup = aws_cloudwatch_log_group.nfw.name }
      log_destination_type = "CloudWatchLogs"
      log_type             = "ALERT"
    }
    log_destination_config {
      log_destination      = { logGroup = aws_cloudwatch_log_group.nfw.name }
      log_destination_type = "CloudWatchLogs"
      log_type             = "FLOW"
    }
  }
}

# --- Routage d'inspection : insérer le pare-feu entre le subnet public (NAT/VPN) et l'IGW ---
# Schéma egress : public --(0/0)--> endpoint pare-feu --(subnet fw, 0/0)--> IGW
#         retour : IGW --(edge, public/24)--> endpoint pare-feu --> public (flux stateful)
locals {
  fw_sync_states = tolist(aws_networkfirewall_firewall.this.firewall_status[0].sync_states)
  fw_endpoint_id = local.fw_sync_states[0].attachment[0].endpoint_id
  # CIDR exacts des 2 subnets publics du siège (10.10.0.0/25 + 10.10.0.128/25) : une route edge
  # par subnet (une RT associée à l'IGW exige des destinations = CIDR de subnet exacts).
  siege_public_cidrs = [for i in [0, 1] : cidrsubnet(cidrsubnet(var.sites["siege"].cidr, 8, 0), 1, i)]
}

# 1) Egress : la route table publique du siège pointe 0/0 vers le endpoint du pare-feu
resource "aws_route" "public_to_fw" {
  route_table_id         = module.network["siege"].public_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.fw_endpoint_id
}

# 2) Le subnet du pare-feu sort, lui, directement par l'IGW
resource "aws_route_table" "firewall" {
  vpc_id = module.network["siege"].vpc_id
  tags   = { Name = "rt-siege-firewall" }
}

resource "aws_route" "fw_to_igw" {
  route_table_id         = aws_route_table.firewall.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = module.network["siege"].igw_id
}

resource "aws_route_table_association" "firewall" {
  subnet_id      = aws_subnet.firewall.id
  route_table_id = aws_route_table.firewall.id
}

# 3) Retour (ingress edge) : l'IGW renvoie le trafic destiné au subnet public via le pare-feu
#    (indispensable pour que le pare-feu stateful voie les DEUX sens du flux)
resource "aws_route_table" "igw_edge" {
  vpc_id = module.network["siege"].vpc_id
  tags   = { Name = "rt-siege-igw-edge" }
}

resource "aws_route" "igw_to_fw" {
  for_each               = toset(local.siege_public_cidrs)
  route_table_id         = aws_route_table.igw_edge.id
  destination_cidr_block = each.value
  vpc_endpoint_id        = local.fw_endpoint_id
}

resource "aws_route_table_association" "igw_edge" {
  gateway_id     = module.network["siege"].igw_id
  route_table_id = aws_route_table.igw_edge.id
}

output "network_firewall" {
  description = "Pare-feu réseau (ARN + endpoint)"
  value = {
    firewall_arn = aws_networkfirewall_firewall.this.arn
    endpoint_id  = local.fw_endpoint_id
    log_group    = aws_cloudwatch_log_group.nfw.name
  }
}
