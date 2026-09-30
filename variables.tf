variable "proxmox_endpoint" {
  description = "Proxmox API endpoint, e.g. https://<host>:8006"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token" {
  description = "Proxmox API token in 'user@realm!token-id=secret' form. Scoped to VM/CT lifecycle on one node/storage only - see README."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (homelab self-signed cert)."
  type        = bool
  default     = true
}

variable "node_name" {
  description = "Proxmox node to provision on."
  type        = string
  sensitive   = true
}

variable "pool_id" {
  description = "Proxmox resource pool the token's role is scoped to - required so the least-privilege token can create a guest at all."
  type        = string
  sensitive   = true
}

variable "template_file_id" {
  description = "Existing LXC template volume ID on the node's storage, e.g. local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
  type        = string
}

variable "storage_id" {
  description = "Storage ID for the container's root disk (e.g. local-lvm)."
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Proxmox network bridge to attach the container to."
  type        = string
  default     = "vmbr0"
}

variable "container_hostname" {
  description = "Hostname for the throwaway container."
  type        = string
  default     = "lab-vm-as-code-demo"
}

variable "container_ipv4_cidr" {
  description = "Static IPv4 address + prefix for the container, e.g. 192.168.1.50/24 - a known-unused address on the lab LAN. Static rather than DHCP so Terraform knows the address at plan time for the provisioner connection below."
  type        = string
  sensitive   = true
}

variable "container_ipv4_gateway" {
  description = "Default gateway for the container's static IPv4 address."
  type        = string
  sensitive   = true
}

variable "ssh_public_key_path" {
  description = "Path to the public half of a dedicated keypair generated only for this demo (never a key used for anything else)."
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to the matching private key, used only by the provisioner connection below - never committed."
  type        = string
  sensitive   = true
}

variable "syslog_target" {
  description = "host:port of the SIEM's syslog input this container forwards logs to (TCP)."
  type        = string
  sensitive   = true
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to reach SSH on the container; everything else is dropped by the Proxmox firewall rule below."
  type        = string
  sensitive   = true
}
