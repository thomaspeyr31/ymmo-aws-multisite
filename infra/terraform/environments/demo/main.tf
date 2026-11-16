# Phase 1 — Réseau : 3 VPC isolés (siège + 2 agences), un appel de module par site.
module "network" {
  source   = "../../modules/network"
  for_each = var.sites

  name       = each.key
  display    = each.value.display
  cidr_block = each.value.cidr
  azs        = var.azs
  project    = var.project

  # Le siège ne gère plus son DHCP via le module : il est repointé vers le DNS
  # de l'AD managé (voir directory.tf / dhcp-ad.tf). Les agences gardent le DNS natif.
  manage_dhcp = each.key != "siege"

  # Le siège fait passer son egress par le Network Firewall (firewall.tf gère la route
  # par défaut publique -> endpoint pare-feu). Les agences sortent directement par l'IGW.
  manage_public_default_route = each.key != "siege"
}
