# Azure node network controls

This module owns a node-subnet NSG and its association to an existing subnet. The infrastructure root supplies the foundation-owned subnet ID; it does not claim ownership of the VNet or subnet.

Internet egress permits TCP 443/80 and UDP 123, then rejects other Internet protocols. Azure platform DNS/IMDS/agent traffic is not specifically denied. Default private VNet flows remain available for AKS control, overlay, membership and PostgreSQL; runtime pod policies provide additional workload isolation later. These NSG rules do not restrict FQDNs or prevent transfers through permitted web ports.