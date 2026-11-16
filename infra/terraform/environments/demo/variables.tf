variable "region" {
  description = "Région AWS de déploiement (Paris)"
  type        = string
  default     = "eu-west-3"
}

variable "project" {
  description = "Nom du projet (tag)"
  type        = string
  default     = "ymmo"
}

variable "azs" {
  description = "Zones de disponibilité (>= 2 pour l'AD managé)"
  type        = list(string)
  default     = ["eu-west-3a", "eu-west-3b"]
}

variable "point_dhcp_to_dc" {
  description = "Si true, le DHCP du siège distribue le DC comme DNS. À ne passer à true QU'APRÈS la promotion du DC (sinon DNS cassé → SSM KO). Par défaut AmazonProvidedDNS (bootstrap)."
  type        = bool
  default     = false
}

variable "sites" {
  description = "Sites Ymmo : CIDR /16 non chevauchants + libellé"
  type = map(object({
    cidr    = string
    display = string
  }))
  default = {
    siege     = { cidr = "10.10.0.0/16", display = "Siège — Aix-en-Provence" }
    marseille = { cidr = "10.21.0.0/16", display = "Agence — Marseille" }
    nimes     = { cidr = "10.22.0.0/16", display = "Agence — Nîmes" }
  }
}
