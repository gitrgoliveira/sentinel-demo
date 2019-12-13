# https://www.terraform.io/docs/providers/vault/index.html
provider "vault" {
  address = var.vault_addr
}

# data "vault_generic_secret" "secret" {
#   path = "kv/test"
# }

data "aws_security_group" "default" {
  vpc_id = data.terraform_remote_state.network.outputs.vpc
  name   = "default"
}

module "postgres" {
  source = "git::https://github.com/clouddrove/terraform-aws-aurora.git?ref=tags/0.12.1"

  name        = "backend-delete"
  application = "demo-delete"
  environment = "test"
  label_order = ["environment", "name", "application"]

  username            = "root"
  database_name       = "test_db"
  engine              = "aurora-postgresql"
  engine_version      = "9.6.9"
  subnets             = data.terraform_remote_state.network.outputs.subnets
  aws_security_group  = [data.aws_security_group.default.id]
  replica_count       = 1
  instance_type       = "db.r4.large"
  apply_immediately   = true
  skip_final_snapshot = true
  publicly_accessible = true
}


resource "vault_mount" "db" {
  path = "demo-postgres"
  type = "database"
}

resource "vault_database_secret_backend_connection" "postgres" {
  backend       = "${vault_mount.db.path}"
  name          = "demo-postgres"
  allowed_roles = ["dev", "prod"]

  postgresql {
    connection_url = "postgres://${module.postgres.rds_cluster_master_username[0]}:${module.postgres.rds_cluster_master_password[0]}@${module.postgres.rds_cluster_endpoint[0]}:${module.postgres.rds_cluster_port[0]}/${module.postgres.rds_cluster_database_name}"
  }
}

resource "vault_database_secret_backend_role" "role" {
  backend             = "${vault_mount.db.path}"
  name                = "demo-role"
  db_name             = "${vault_database_secret_backend_connection.postgres.name}"
  creation_statements = ["CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';"]
  default_ttl         = 600 # 10m
  max_ttl             = 7200 # 2h
}
