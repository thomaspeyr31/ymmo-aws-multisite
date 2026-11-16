output "vpcs" {
  description = "Récapitulatif des VPC créés par site"
  value = {
    for k, m in module.network : k => {
      vpc_id        = m.vpc_id
      cidr          = m.vpc_cidr
      subnets       = m.subnets_by_tier
      nat_public_ip = m.nat_public_ip
    }
  }
}

output "postes_agence" {
  description = "Postes de travail d'agence (instance_id + IP privée) pour SSM / jonction"
  value = {
    for k, i in aws_instance.poste : k => {
      instance_id = i.id
      private_ip  = i.private_ip
      subnet_id   = i.subnet_id
    }
  }
}

output "fileserver" {
  description = "Serveur de fichiers du siège (instance_id + IP privée)"
  value = {
    instance_id = aws_instance.fileserver.id
    private_ip  = aws_instance.fileserver.private_ip
  }
}

output "vpn_gateway" {
  description = "Passerelle IPSec nomade (IP publique + instance_id)"
  value = {
    instance_id = aws_instance.vpn.id
    public_ip   = aws_eip.vpn.public_ip
    eap_user    = local.vpn_eap_user
  }
}

output "vpn_eap_password" {
  description = "Mot de passe EAP du compte VPN nomade (lecture: terraform output -raw vpn_eap_password)"
  value       = random_password.vpn_eap.result
  sensitive   = true
}
