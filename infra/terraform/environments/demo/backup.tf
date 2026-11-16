# Step 06 — Plan de sauvegarde (AWS Backup).
# On sauvegarde la VALEUR : le serveur de fichiers (données métier) + le DC (annuaire).
# PAS les postes (jetables, données centralisées sur FILESRV). Sélection PAR TAG Backup=true.

resource "aws_backup_vault" "ymmo" {
  name = "ymmo-vault"
  tags = { Name = "ymmo-vault" }
}

resource "aws_backup_plan" "ymmo" {
  name = "ymmo-plan"

  # Sauvegarde quotidienne, rétention 7 jours.
  rule {
    rule_name         = "daily-7d"
    target_vault_name = aws_backup_vault.ymmo.name
    schedule          = "cron(0 2 * * ? *)" # 02:00 UTC chaque jour
    start_window      = 60
    completion_window = 180
    lifecycle {
      delete_after = 7
    }
  }

  # Sauvegarde hebdomadaire conservée plus longtemps (rétention 35 jours).
  rule {
    rule_name         = "weekly-35d"
    target_vault_name = aws_backup_vault.ymmo.name
    schedule          = "cron(0 3 ? * SUN *)" # dimanche 03:00 UTC
    start_window      = 60
    completion_window = 300
    lifecycle {
      delete_after = 35
    }
  }

  tags = { Name = "ymmo-plan" }
}

# Rôle de service assumé par AWS Backup
resource "aws_iam_role" "backup" {
  name = "ymmo-backup"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "ymmo-backup" }
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# Sélection des ressources à sauvegarder : par TAG Backup=true (posé sur DC + FILESRV)
resource "aws_backup_selection" "ymmo" {
  name         = "ymmo-tagged"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.ymmo.id

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }
}

output "backup" {
  description = "Plan de sauvegarde AWS Backup"
  value = {
    vault = aws_backup_vault.ymmo.name
    plan  = aws_backup_plan.ymmo.name
  }
}
