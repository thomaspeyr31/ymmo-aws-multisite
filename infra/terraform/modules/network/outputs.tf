output "vpc_id" {
  description = "ID du VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR du VPC"
  value       = aws_vpc.this.cidr_block
}

output "subnets_by_tier" {
  description = "IDs de subnets regroupés par tier (public / serveurs / postes)"
  value = {
    for tier in keys(local.tier_netnum) :
    tier => [for k, s in aws_subnet.this : s.id if local.subnets[k].tier == tier]
  }
}

output "nat_public_ip" {
  description = "IP publique de sortie (NAT Gateway)"
  value       = aws_eip.nat.public_ip
}

output "igw_id" {
  description = "ID de l'Internet Gateway (pour le routage egress via pare-feu)"
  value       = aws_internet_gateway.this.id
}

output "public_route_table_id" {
  description = "ID de la route table publique (pour réorienter l'egress vers le pare-feu)"
  value       = aws_route_table.public.id
}

output "public_subnet_ids" {
  description = "Subnets publics (NAT + passerelle VPN)"
  value       = local.public_subnet_ids
}

output "private_route_table_id" {
  description = "ID de la route table privée (serveurs + postes) — pour les routes vers le TGW"
  value       = aws_route_table.private.id
}

output "serveurs_subnet_ids" {
  description = "Subnets serveurs (1 par AZ) — utilisés pour l'attachment TGW"
  value       = [for k, s in aws_subnet.this : s.id if local.subnets[k].tier == "serveurs"]
}
