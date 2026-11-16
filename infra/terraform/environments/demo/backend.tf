# Backend S3 (région Paris). Le nom du bucket n'est pas versionné : il est passé à
# l'init via la variable d'environnement TF_STATE_BUCKET
#   terraform init -backend-config="bucket=$TF_STATE_BUCKET"
# Verrou d'état NATIF S3 (use_lockfile) — pas de table DynamoDB requise (TF >= 1.10).
# Préfixe dédié au projet : ymmo-filerouge/demo (vérifié libre).
terraform {
  backend "s3" {
    key          = "ymmo-filerouge/demo/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
  }
}
