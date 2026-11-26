terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

variable "do_token" {}
variable "pvt_key" {}

provider "digitalocean" {
  token = var.do_token
}

data "digitalocean_ssh_key" "terraform" {
  name = "test_task_ssh"
}

resource "null_resource" "create_ansible_inventory" {
  # re-run the provisioner when the droplet IP changes (recreate, resize migration)
  triggers = {
    droplet_ip = digitalocean_droplet.droplet.ipv4_address
  }

  provisioner "local-exec" {
    command = <<EOT
cat > ${path.module}/../ansible/inventory.yml <<EOF
all:
  hosts:
    droplet:
      ansible_host: ${digitalocean_droplet.droplet.ipv4_address}
      ansible_user: root
      # ansible_ssh_private_key_file: ${abspath(var.pvt_key)}
EOF
EOT
  }
}
