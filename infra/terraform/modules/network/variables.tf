variable "name" {
  description = "Identifiant court du site (siege, marseille, nimes)"
  type        = string
}

variable "display" {
  description = "Libellé lisible du site (pour les tags)"
  type        = string
  default     = ""
}

variable "cidr_block" {
  description = "CIDR /16 du VPC (ex: 10.10.0.0/16)"
  type        = string
}

variable "azs" {
  description = "Zones de disponibilité (>= 2, requis pour l'AD managé sur le tier serveurs)"
  type        = list(string)
}

variable "project" {
  description = "Nom du projet (tag)"
  type        = string
  default     = "ymmo"
}

variable "manage_dhcp" {
  description = "Si false, le module ne gère pas le DHCP options set du VPC (laissé à un autre composant, ex. repoint vers le DNS de l'AD au step 02)."
  type        = bool
  default     = true
}

variable "dns_servers" {
  description = "Serveurs DNS distribués par le DHCP options set."
  type        = list(string)
  default     = ["AmazonProvidedDNS"]
}

variable "manage_public_default_route" {
  description = "Si false, le module ne crée PAS la route par défaut publique (0.0.0.0/0 -> IGW) : elle est gérée hors module (ex. réorientée vers un AWS Network Firewall au siège, step 05)."
  type        = bool
  default     = true
}
