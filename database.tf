# https://www.terraform.io/docs/providers/vault/index.html
provider "vault" {
  address = "https://${var.vault_host}:8200"
}

# data "vault_generic_secret" "secret" {
#   path = "kv/test"
# }

data "aws_security_group" "default" {
  vpc_id = data.terraform_remote_state.network.outputs.vpc
  name   = "default"
}

resource "aws_security_group_rule" "allow_all" {
  type      = "ingress"
  from_port = module.aurora.rds_cluster_port[0]
  to_port   = module.aurora.rds_cluster_port[0]
  protocol  = "tcp"
  # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = data.aws_security_group.default.id
}

module "aurora" {
  source = "git::https://github.com/clouddrove/terraform-aws-aurora.git?ref=tags/0.12.1"

  name        = "backend-delete"
  application = "demo-delete"
  environment = "test"
  label_order = ["environment", "name", "application"]

  username            = "admin"
  database_name       = "test_db"
  engine              = "aurora-mysql"
  engine_version      = "5.7.12"
  subnets             = data.terraform_remote_state.network.outputs.subnets
  aws_security_group  = [data.aws_security_group.default.id]
  replica_count       = 1
  instance_type       = "db.t2.medium"
  apply_immediately   = true
  skip_final_snapshot = true
  publicly_accessible = true
}


resource "vault_mount" "db" {
  path = "demo-mysql"
  type = "database"
}

resource "vault_database_secret_backend_connection" "mysql" {
  backend       = vault_mount.db.path
  name          = "demo-mysql"
  allowed_roles = ["demo-role"]

  mysql_aurora {
    connection_url       = "${module.aurora.rds_cluster_master_username[0]}:${module.aurora.rds_cluster_master_password[0]}@tcp(${module.aurora.rds_cluster_endpoint[0]}:${module.aurora.rds_cluster_port[0]})/"
    max_open_connections = 256
  }

  verify_connection = true
}

resource "vault_database_secret_backend_role" "role" {
  backend             = vault_mount.db.path
  name                = "demo-role"
  db_name             = vault_database_secret_backend_connection.mysql.name
  creation_statements = ["CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT ON *.* TO '{{name}}'@'%';"]
  default_ttl         = 600  # 10m
  max_ttl             = 7200 # 2h
}
