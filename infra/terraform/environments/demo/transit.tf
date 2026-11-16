# Step 03 — Interconnexion hub-and-spoke via AWS Transit Gateway.
# Le siège est le HUB ; les agences sont des spokes. Segmentation par les TABLES DE
# ROUTAGE du TGW : agence ↔ siège autorisé, agence ↔ agence interdit.

resource "aws_ec2_transit_gateway" "ymmo" {
  description = "Ymmo - hub-and-spoke (siege = hub)"
  # On gère l'association/propagation manuellement (pas la table par défaut).
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  tags                            = { Name = "tgw-ymmo" }
}

# --- 1 attachment par VPC (dans les subnets serveurs, 1 par AZ) ---
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = var.sites

  transit_gateway_id = aws_ec2_transit_gateway.ymmo.id
  vpc_id             = module.network[each.key].vpc_id
  subnet_ids         = module.network[each.key].serveurs_subnet_ids

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = "tgwattach-${each.key}", Site = each.key }
}

# --- 2 tables de routage TGW ---
resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.ymmo.id
  tags               = { Name = "tgw-rt-hub" } # associée au siège : voit les 3 sites
}

resource "aws_ec2_transit_gateway_route_table" "spokes" {
  transit_gateway_id = aws_ec2_transit_gateway.ymmo.id
  tags               = { Name = "tgw-rt-spokes" } # associée aux agences : ne voit que le siège
}

# --- Associations : qui utilise quelle table ---
resource "aws_ec2_transit_gateway_route_table_association" "siege" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["siege"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

resource "aws_ec2_transit_gateway_route_table_association" "spokes" {
  for_each                       = { for k, v in var.sites : k => v if k != "siege" }
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes.id
}

# --- Propagations : ce que chaque table APPREND ---
# rt-hub apprend les 3 sites (le hub voit tout).
resource "aws_ec2_transit_gateway_route_table_propagation" "hub" {
  for_each                       = var.sites
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

# rt-spokes n'apprend QUE le siège (les agences ne se voient pas entre elles).
resource "aws_ec2_transit_gateway_route_table_propagation" "spokes_to_siege" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["siege"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes.id
}

# --- Routes côté VPC (dans la route table privée) vers les CIDR distants via le TGW ---
locals {
  # siège -> toutes les agences ; chaque agence -> siège uniquement (agence↔agence absent)
  vpc_tgw_routes = merge(
    { for k, v in var.sites : "siege-to-${k}" => { site = "siege", cidr = v.cidr } if k != "siege" },
    { for k, v in var.sites : "${k}-to-siege" => { site = k, cidr = var.sites["siege"].cidr } if k != "siege" }
  )
}

resource "aws_route" "tgw" {
  for_each               = local.vpc_tgw_routes
  route_table_id         = module.network[each.value.site].private_route_table_id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = aws_ec2_transit_gateway.ymmo.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

output "transit_gateway" {
  description = "Transit Gateway et ses tables de routage"
  value = {
    id              = aws_ec2_transit_gateway.ymmo.id
    rt_hub          = aws_ec2_transit_gateway_route_table.hub.id
    rt_spokes       = aws_ec2_transit_gateway_route_table.spokes.id
    attachments     = { for k, a in aws_ec2_transit_gateway_vpc_attachment.this : k => a.id }
    vpc_routes_adds = keys(local.vpc_tgw_routes)
  }
}
