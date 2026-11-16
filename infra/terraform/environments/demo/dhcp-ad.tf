# Step 02 — Repointage DHCP du SIÈGE vers le DNS de l'AD (zone privée ymmo.lan).
# C'est l'étape pivot : sans ça, ymmo.lan est inrésolvable → jonction de domaine impossible.
# (Le module réseau ne gère plus le DHCP du siège : manage_dhcp=false dans main.tf.)

resource "aws_vpc_dhcp_options" "ad_siege" {
  domain_name = "ymmo.lan"
  # DNS = le DC seulement APRÈS sa promotion (var.point_dhcp_to_dc=true) ; sinon DNS
  # natif AWS pour que l'agent SSM puisse résoudre ses endpoints (bootstrap).
  domain_name_servers = var.point_dhcp_to_dc ? [aws_instance.dc.private_ip] : ["AmazonProvidedDNS"]
  tags                = { Name = "dhcp-siege-ad", Site = "siege" }
}

resource "aws_vpc_dhcp_options_association" "ad_siege" {
  vpc_id          = module.network["siege"].vpc_id
  dhcp_options_id = aws_vpc_dhcp_options.ad_siege.id
}
