terraform {
  backend "remote" {
    organization = "hc-emea-sentinel-demo"
    workspaces {
      name = "sentinel-demo-stack"
    }
  }
}
provider "vault" {
  address = "${var.vault_addr}"
}
data "vault_generic_secret" "secret" {
  path = "kv/test"
}

provider "aws" {
  region = "eu-west-2"
}

// Workspace Data
data "terraform_remote_state" "network" {
  backend = "remote"

  config = {
    hostname     = "app.terraform.io"
    organization = "hc-emea-sentinel-demo"
    workspaces = {
      name = "sentinel-demo-network"
    }
  } //config
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.small"
  subnet_id     = "${data.terraform_remote_state.network.outputs.subnets[0]}"
  tags = {
    Name = "test_server"
    owner = "StepStone"
    tag = "${data.vault_generic_secret.secret.data["message"]}"
  }
}

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 2.0"

  identifier = "demodb"

  engine            = "mysql"
  engine_version    = "5.7.19"
  instance_class    = "db.t2.large"
  allocated_storage = 5

  name     = "demodb"
  username = "user"
  password = "YourPwdShouldBeLongAndSecure!"
  port     = "3306"

  iam_database_authentication_enabled = true

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  tags = {
    Owner       = "user"
    Environment = "dev"
  }

  # DB subnet group
  subnet_ids = data.terraform_remote_state.network.outputs.subnets

  # DB parameter group
  family = "mysql5.7"

  # DB option group
  major_engine_version = "5.7"

  # Snapshot name upon DB deletion
  final_snapshot_identifier = "demodb"

  # Database Deletion Protection
  deletion_protection = false

  parameters = [
    {
      name = "character_set_client"
      value = "utf8"
    },
    {
      name = "character_set_server"
      value = "utf8"
    }
  ]

  options = [
    {
      option_name = "MARIADB_AUDIT_PLUGIN"

      option_settings = [
        {
          name  = "SERVER_AUDIT_EVENTS"
          value = "CONNECT"
        },
        {
          name  = "SERVER_AUDIT_FILE_ROTATIONS"
          value = "37"
        },
      ]
    },
  ]
}