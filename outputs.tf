output "container_id" {
  description = "Proxmox VMID of the provisioned container."
  value       = proxmox_virtual_environment_container.lab.id
}

output "container_ip" {
  description = "Static IPv4 address of the container."
  value       = split("/", var.container_ipv4_cidr)[0]
  sensitive   = true
}
