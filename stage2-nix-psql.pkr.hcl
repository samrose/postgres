variable "profile" {
  type    = string
  default = "${env("AWS_PROFILE")}"
}

variable "ami_regions" {
  type    = list(string)
  default = ["ap-southeast-2"]
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "region" {
  type    = string
}

variable "ami_name" {
  type    = string
  default = "supabase-postgres"
}

variable "postgres-version" {
  type = string
  default = ""
}

variable "git-head-version" {
  type = string
  default = "unknown"
}

variable "packer-execution-id" {
  type = string
  default = "unknown"
}

variable "force-deregister" {
  type    = bool
  default = false
}

packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "ubuntu" {
  ami_name      = "${var.ami_name}-${var.postgres-version}-nix"
  instance_type = "c6g.4xlarge"
  region        = "${var.region}"
  source_ami_filter {
    filters = {
      name   = "${var.ami_name}-${var.postgres-version}-stage-1"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon", "self"]
  }
  ssh_username = "ubuntu"
  ena_support = true

}

build {
  name = "nix-packer-ubuntu"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]

  # Copy ansible playbook
  provisioner "shell" {
    inline = ["mkdir /tmp/ansible-playbook"]
  }

  provisioner "file" {
    source = "ansible-nix/tasks/stage2"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "file" {
    source      = "ansible-nix/files"
    destination = "/tmp/ansible-playbook/files"
  }

  provisioner "file" {
    source = "migrations"
    destination = "/tmp"
  }

  provisioner "file" {
    source       = "ebssurrogate/files/unit-tests"
    destination  = "/tmp/unit-tests"
  }

  provisioner "shell" {
     script = "scripts/nix-provision.sh"
  }
  
}