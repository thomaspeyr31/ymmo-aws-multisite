# Module network — 1 VPC d'un site Ymmo (siège ou agence), topologie 3 tiers / 2 AZ.
# Tiers à offsets fixes (convention d'adressage commune à tous les sites) :
#   public = x.x.0.0/24 · serveurs = x.x.10.0/24 · postes = x.x.20.0/24
# Chaque /24 est découpé en deux /25 répartis sur les AZ (serveurs multi-AZ = pré-requis AD).

locals {
  tier_netnum = { public = 0, serveurs = 10, postes = 20 }
  tier_public = { public = true, serveurs = false, postes = false }

  subnets = merge([
    for tier, netnum in local.tier_netnum : {
      for idx, az in var.azs :
      "${tier}-${idx}" => {
        tier   = tier
        az     = az
        public = local.tier_public[tier]
        cidr   = cidrsubnet(cidrsubnet(var.cidr_block, 8, netnum), 1, idx)
      }
    }
  ]...)

  tags = {
    Project = var.project
    Site    = var.name
    Display = var.display
  }

  public_subnet_ids = [for k, s in aws_subnet.this : s.id if local.subnets[k].public]
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = "vpc-${var.name}" })
}

resource "aws_subnet" "this" {
  for_each          = local.subnets
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags = merge(local.tags, {
    Name = "subnet-${var.name}-${each.key}"
    Tier = each.value.tier
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "igw-${var.name}" })
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "eip-nat-${var.name}" })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = local.public_subnet_ids[0]
  tags          = merge(local.tags, { Name = "nat-${var.name}" })
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "rt-public-${var.name}" })
}

# Route par défaut publique en ressource SÉPARÉE (et non inline) : permet de la réorienter
# hors module (egress via Network Firewall au siège). Désactivable via manage_public_default_route.
resource "aws_route" "public_default" {
  count                  = var.manage_public_default_route ? 1 : 0
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }
  tags = merge(local.tags, { Name = "rt-private-${var.name}" })

  # Les routes vers le Transit Gateway (hub-and-spoke, step 03) sont gérées hors
  # module via des ressources aws_route dédiées (environments/demo/transit.tf).
  # On ignore donc la liste `route` ici pour éviter que la définition inline (NAT)
  # ne supprime ces routes TGW à chaque plan.
  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "public" {
  for_each       = { for k, s in aws_subnet.this : k => s if local.subnets[k].public }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each       = { for k, s in aws_subnet.this : k => s if !local.subnets[k].public }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# DHCP options : DNS natif du VPC par défaut. Désactivable (manage_dhcp=false) pour
# laisser le step 02 repointer le siège vers le DNS de l'AD managé.
resource "aws_vpc_dhcp_options" "this" {
  count               = var.manage_dhcp ? 1 : 0
  domain_name_servers = var.dns_servers
  tags                = merge(local.tags, { Name = "dhcp-${var.name}" })
}

resource "aws_vpc_dhcp_options_association" "this" {
  count           = var.manage_dhcp ? 1 : 0
  vpc_id          = aws_vpc.this.id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}
