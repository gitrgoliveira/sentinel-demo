# https://www.terraform.io/docs/providers/vault/index.html

# data "vault_generic_secret" "secret" {
#   path = "kv/test"
# }

data "aws_security_group" "default" {
  vpc_id = data.terraform_remote_state.network.outputs.vpc
  name   = "default"
}

resource "aws_security_group_rule" "allow_all" {
  type      = "ingress"
  from_port = aws_db_instance.default.port
  to_port   = aws_db_instance.default.port
  protocol  = "tcp"
  # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = data.aws_security_group.default.id
}

resource "aws_db_instance" "default" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  name                 = "ricdemodeletedb"
  username             = "foo"
  password             = "foobarbaz"
  parameter_group_name = "default.mysql5.7"
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
    connection_url       = "foo:foobarbaz@tcp(${aws_db_instance.default.endpoint})/"
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
