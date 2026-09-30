# lab-vm-as-code

Terraform (bpg/proxmox provider) that provisions, hardens, and tears down
one throwaway Debian LXC container on a home Proxmox lab: key-only SSH,
a hypervisor-level default-deny firewall with a single allowed inbound
rule, and log forwarding to a SIEM. Applied against real infrastructure,
verified, and destroyed - not just written and left unrun.

## What this is

A small, honest Infrastructure-as-Code exercise: one container, provisioned
and torn down by `terraform apply` / `terraform destroy` against a real
(home-lab) Proxmox cluster, with every claim below backed by something
actually run and actually verified, not asserted.

## What this is not

Not a claim of managing production infrastructure at scale, not a
multi-environment/multi-cloud Terraform setup, and not a claim that
Proxmox's firewall or SDN internals were already fully understood -
several real permission and enforcement gaps were hit and fixed along the
way (see "What actually happened," below), which is closer to how this
kind of work goes in practice than a clean first-try log would be.

## Design

- **Least-privilege credential**: a dedicated Proxmox API token
  (`terraform@pve`, not root), with a custom role granting only
  VM/CT-lifecycle privileges, scoped via ACL to exactly the node, storage,
  resource pool, and SDN zone path this needs - nothing cluster-wide.
- **Key-only SSH from creation**: the container is created with a
  dedicated SSH keypair generated only for this project (never reused
  elsewhere) injected via cloud-init-style `user_account`, no password set
  at any point.
- **Post-boot hardening, explicit**: a `remote-exec` provisioner
  explicitly sets `PasswordAuthentication no` and
  `PermitRootLogin prohibit-password` in `sshd_config` - belt and
  suspenders on top of never having set a password.
- **Hypervisor-level firewall, not just in-guest**: a
  `proxmox_virtual_environment_firewall_options` + `..._firewall_rules`
  resource pair sets a default-deny (`DROP`) inbound policy on the
  container with a single `ACCEPT` rule for SSH from the lab subnet -
  enforced by Proxmox itself, independent of whatever the guest's own
  iptables/nftables state ends up being.
- **SIEM log forwarding**: the same provisioner configures rsyslog to
  forward all guest logs to the lab's Splunk instance over TCP.
- **Static IP, not DHCP**: the container gets a fixed address so Terraform
  knows it at plan time for the provisioner's SSH connection, rather than
  needing a separate step to discover a DHCP lease after the fact.
- **Internal addresses stay out of this repo**: `terraform.tfvars` (real
  IPs, hostnames, and the API token) is gitignored;
  `terraform.tfvars.example` documents every variable with a placeholder
  value only.

## What actually happened

This was applied against a real home-lab Proxmox cluster, not just
written. Several real issues came up during that process and are recorded
here rather than edited out, because working through them is exactly what
this repo is meant to demonstrate:

1. **First `apply` failed outright**: the initial least-privilege token
   only had a role granted on the target node path, which is not the ACL
   branch Proxmox actually checks for guest creation. Fixed by creating a
   dedicated resource pool and granting the role on the pool instead -
   narrower than a blanket `/vms` grant, since it scopes to only guests
   inside that pool.
2. **Second failure, more specific**: `SDN.Use` denied on the bridge path
   (`/sdn/zones/.../vmbr0`). Even a cluster with no SDN zones configured
   still gates plain-bridge NIC attachment through an implicit zone for
   permission purposes on modern Proxmox. Fixed by granting `SDN.Use` on
   that exact path, not a blanket SDN grant.
3. **DHCP vs. static IP**: the first full container create succeeded, but
   the post-boot provisioner's SSH connection failed - it had been
   configured to read back the container's IP config, which only echoes
   the literal string `"dhcp"` from the input, not the address actually
   leased at boot. Fixed by switching the container to a static IP so
   Terraform has a real address to connect to at plan time, instead of
   trying to discover a DHCP lease after the fact.
4. **The firewall rule silently didn't work** on the first successful
   apply: the config looked correct (default-deny policy, one allow rule
   for SSH) and Proxmox's own API confirmed it, but a real test - starting
   a listener inside the container on another port and trying to reach it
   from outside - showed it was still open. Two separate things were
   wrong at once: the container's network interface itself needed its own
   `firewall = true` flag (a per-NIC opt-in, separate from the per-guest
   firewall config), and the datacenter-wide firewall switch was off
   entirely (a cluster-level toggle that gates whether *any* per-guest
   firewall config does anything at all). Fixed both, then re-ran the same
   positive test (listener up, port unreachable from outside, SSH still
   reachable) to confirm before moving on - config alone wasn't accepted
   as proof.

## Evidence trail

Every claim above was checked, not assumed:

- `terraform apply` succeeded (container created, firewall options/rules
  created, provisioner ran).
- SSH into the container over the dedicated key confirmed
  `PasswordAuthentication no` and `PermitRootLogin prohibit-password` in
  `sshd_config`, and confirmed `rsyslog` active with the forwarding rule in
  place.
- Firewall enforcement was tested positively, not just read back from
  config: started a listener on a non-SSH port inside the container,
  confirmed it was unreachable from outside while SSH remained reachable.
- `terraform plan` after all fixes reported **no changes** - a second,
  independent run confirming the applied state matches the configuration
  exactly (idempotency).
- `terraform destroy` cleanly removed all four resources (container,
  firewall options, firewall rules, the hardening provisioner's tracking
  resource) with nothing left behind.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Provider, container, firewall options/rules, hardening provisioner |
| `variables.tf` | All configurable inputs, each documented |
| `outputs.tf` | Container ID and IP (marked sensitive) |
| `terraform.tfvars.example` | Every variable with a placeholder value - copy to `terraform.tfvars` (gitignored) and fill in real values |

## Running this yourself

```bash
cp terraform.tfvars.example terraform.tfvars   # fill in real values
ssh-keygen -t ed25519 -f .secrets/lab-vm-as-code -N ""   # dedicated key, not one you use elsewhere
terraform init
terraform plan -out=tfplan
terraform apply tfplan
# ... verify, then:
terraform destroy
```
