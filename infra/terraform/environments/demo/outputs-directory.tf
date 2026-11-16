output "ad_admin_password" {
  description = "Mot de passe du compte Administrateur du domaine ymmo.lan (terraform output -raw ad_admin_password)"
  value       = random_password.ad_admin.result
  sensitive   = true
}

output "dc" {
  description = "Contrôleur de domaine auto-géré (DNS de ymmo.lan)"
  value = {
    instance_id = aws_instance.dc.id
    private_ip  = aws_instance.dc.private_ip
  }
}

output "ec2_admin" {
  description = "Poste d'administration Windows (membre du domaine, accès SSM Fleet Manager)"
  value = {
    instance_id = aws_instance.admin.id
    private_ip  = aws_instance.admin.private_ip
  }
}
