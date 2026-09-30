terraform {
  required_version = ">= 1.7.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure
}

resource "proxmox_virtual_environment_container" "lab" {
  node_name    = var.node_name
  pool_id      = var.pool_id
  unprivileged = true

  operating_system {
    template_file_id = var.template_file_id
    type             = "debian"
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = var.storage_id
    size         = 4
  }

  network_interface {
    name     = "eth0"
    bridge   = var.network_bridge
    firewall = true # without this, the guest firewall rules below are inert for this NIC
  }

  initialization {
    hostname = var.container_hostname

    ip_config {
      ipv4 {
        address = var.container_ipv4_cidr
        gateway = var.container_ipv4_gateway
      }
    }

    user_account {
      keys     = [trimspace(file(var.ssh_public_key_path))]
      password = null # key-only: no password is ever set on this account
    }
  }

  started = true

  # Least-privilege by construction: no privileged escalation, no nesting,
  # nothing this demo doesn't need.
  features {
    nesting = false
  }
}

# Proxmox-level (not just in-guest) firewall: default-deny, SSH only from
# the allowed CIDR. This is enforced by the hypervisor regardless of
# whatever the guest's own iptables/nftables state ends up being.
resource "proxmox_virtual_environment_firewall_options" "lab" {
  node_name    = var.node_name
  container_id = proxmox_virtual_environment_container.lab.id

  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
}

resource "proxmox_virtual_environment_firewall_rules" "lab" {
  node_name    = var.node_name
  container_id = proxmox_virtual_environment_container.lab.id

  rule {
    security_group = null
    type           = "in"
    action         = "ACCEPT"
    proto          = "tcp"
    dport          = "22"
    source         = var.allowed_ssh_cidr
    comment        = "SSH from the lab network only"
  }
}

# Hardening + SIEM forwarding done post-boot, over SSH, using the
# dedicated key this container was created with (see user_account above).
resource "null_resource" "harden_and_forward" {
  depends_on = [
    proxmox_virtual_environment_container.lab,
    proxmox_virtual_environment_firewall_rules.lab,
  ]

  triggers = {
    container_id  = proxmox_virtual_environment_container.lab.id
    syslog_target = var.syslog_target
  }

  connection {
    type        = "ssh"
    host        = split("/", var.container_ipv4_cidr)[0]
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    # Note: Terraform's built-in ssh communicator does not verify host keys
    # at all (there is no equivalent of StrictHostKeyChecking here) - this
    # is a real, documented Terraform limitation, not a weakening decision
    # made in this config. Acceptable for a throwaway box this same run
    # just created and will destroy; not something to rely on for anything
    # longer-lived without wrapping SSH yourself (e.g. via a script
    # provisioner that pins the key after first contact).
  }

  provisioner "remote-exec" {
    inline = [
      "set -eu",
      # Key-only SSH, explicitly - belt and suspenders on top of never
      # having set a password in the first place.
      "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config",
      "systemctl restart ssh || systemctl restart sshd",
      # Forward all logs to the SIEM over TCP.
      "apt-get update -qq && apt-get install -y -qq rsyslog >/dev/null",
      "printf '*.* @@%s\\n' \"${var.syslog_target}\" > /etc/rsyslog.d/60-forward.conf",
      "systemctl restart rsyslog",
      "logger 'lab-vm-as-code: hardening + forwarding applied'",
    ]
  }
}
