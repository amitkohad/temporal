# Azure Container Registry

Use `name`, `resource_group_name`, and `location` with the approved globally available name. Staging defaults to Basic with authenticated public access and no administrator password. `writer_object_ids` grants AcrPush only at registry scope. The AKS module grants its kubelet AcrPull.

Private access requires `sku = "Premium"`, `private_access = true`, `private_endpoint_subnet_id`, and `virtual_network_id`. The module owns the ACR private DNS zone and VNet link. Share or import an existing zone instead of giving multiple modules ownership of the same zone.

The `reference` output contains resource ID, name, login server and private access status; it contains no credentials. Destruction is guarded. Apply requires Terraform management-plane permissions and role assignment authority. This uses classic registry RBAC; do not switch the registry to ABAC without updating AcrPull and AcrPush assignments.

Validate with Terraform init, validate and test in this directory. Tests mock Azure and perform no provisioning.