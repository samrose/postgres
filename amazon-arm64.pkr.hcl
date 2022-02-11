variable "ami" {
  type    = string
  default = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-arm64-server-*"
}

variable "profile" {
  type    = string
  default = "${env("AWS_PROFILE")}"
}

variable "ami_name" {
  type    = string
  default = "supabase-postgres-fastboot"
}

variable "ami_regions" {
  type    = list(string)
  default = ["ap-southeast-2"]
}

variable "ansible_arguments" {
  type    = string
  default = "--skip-tags,install-postgrest,--skip-tags,install-pgbouncer,--skip-tags,install-supabase-internal,ebssurrogate_mode='true'"
}

variable "aws_access_key" {
  type    = string
  default = ""
}

variable "aws_secret_key" {
  type    = string
  default = ""
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "region" {
  type    = string
}

variable "build-vol" {
  type    = string
  default = "xvdc"
}

# ccache docker image details
variable "docker_user" {
  type    = string
  default = ""
}

variable "docker_passwd" {
  type    = string
  default = ""
}

variable "docker_image" {
  type    = string
  default = ""
}

variable "docker_image_tag" {
  type    = string
  default = "latest"
}

locals {
  creator = "packer"
}


# source block
source "amazon-ebssurrogate" "source" {
  profile = "${var.profile}"
  #access_key    = "${var.aws_access_key}"
  ami_name = "${var.ami_name}-arm64-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  ami_description = "Supabase AMI (arm64-ext4-10g)"
  ami_virtualization_type = "hvm"
  ami_architecture = "arm64"
  ami_regions   = "${var.ami_regions}"
  instance_type = "t4g.2xlarge"
  region       = "${var.region}"
  #secret_key   = "${var.aws_secret_key}"

  # Use latest official ubuntu focal ami owned by Canonical.
  source_ami_filter {
    filters = {
      virtualization-type = "hvm"
      name = "${var.ami}"
      root-device-type = "ebs"
    }
    owners = [ "099720109477" ]
    most_recent = true
   }
  ena_support = true
  launch_block_device_mappings {
    device_name = "/dev/xvdf"
    delete_on_termination = true
    volume_size = 10
    volume_type = "gp2"
    encrypted = true
   }

  launch_block_device_mappings {
    device_name           = "/dev/${var.build-vol}"
    delete_on_termination = true
    volume_size           = 16
    volume_type           = "gp2"
    omit_from_artifact    = true
  }

  run_tags = {
    Name = "Supabase AMI Builder(arm64-ext4-10G)"
    creator = "packer"
  }
  run_volume_tags = {
    Name = "Supabase AMI Builder(arm64-ext4-10G)"
    creator = "packer"
  }
  snapshot_tags = {
    creator = "packer"
  }
  tags = {
    appType = "postgres"
    creator = "packer"
    environment = "${var.environment}"
    Name = "Supabase AMI (arm64-ext4-10G)"
  }

  communicator = "ssh"
  ssh_pty = true
  ssh_username = "ubuntu"
  ssh_timeout = "5m"

  ami_root_device {
    source_device_name = "/dev/xvdf"
    device_name = "/dev/xvda"
    delete_on_termination = true
    volume_size = 10
    volume_type = "gp2"
  }
}

# a build block invokes sources and runs provisioning steps on them.
build {
  sources = ["source.amazon-ebssurrogate.source"]

  provisioner "file" {
    source = "ebssurrogate/files/sources-arm64.cfg"
    destination = "/tmp/sources.list"
  }

  provisioner "file" {
    source = "ebssurrogate/files/ebsnvme-id"
    destination = "/tmp/ebsnvme-id"
  }

  provisioner "file" {
    source = "ebssurrogate/files/70-ec2-nvme-devices.rules"
    destination = "/tmp/70-ec2-nvme-devices.rules"
  }

  provisioner "file" {
    source = "ebssurrogate/scripts/chroot-bootstrap.sh"
    destination = "/tmp/chroot-bootstrap.sh"
  }

  provisioner "file" {
    source = "ebssurrogate/files/cloud.cfg"
    destination = "/tmp/cloud.cfg"
  }

  provisioner "file" {
    source = "ebssurrogate/files/vector.timer"
    destination = "/tmp/vector.timer"
  }

  # Copy ansible playbook
  provisioner "shell" {
    inline = ["mkdir /tmp/ansible-playbook"]
  }

  provisioner "file" {
    source = "ansible"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "file" {
    source = "scripts"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "shell" {
    environment_vars = [
      "ARGS=${var.ansible_arguments}",
      "DOCKER_USER=${var.docker_user}",
      "DOCKER_PASSWD=${var.docker_passwd}",
      "DOCKER_IMAGE=${var.docker_image}",
      "DOCKER_IMAGE_TAG=${var.docker_image_tag}"
    ]
    script = "ebssurrogate/scripts/surrogate-bootstrap.sh"
    execute_command = "sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
    start_retry_timeout = "5m"
    skip_clean = true
  }

  provisioner "file" {
    source = "/tmp/ansible.log"
    destination = "/tmp/ansible.log"
    direction = "download"
  }
}
