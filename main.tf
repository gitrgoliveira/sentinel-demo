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
data "vault_generic_secret" "rundeck_auth" {
  path = "pki/issue/consul-service common_name=nginx.service.consul ttl=90m"
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
  instance_type = "t2.micro"
  subnet_id     = "${data.terraform_remote_state.network.outputs.subnets[0]}"
  tags = {
    Name = "test_server"
    owner = "StepStone"
  }
}
