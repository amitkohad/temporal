# Platform handoff contract

This provider-neutral root validates explicit nonsecret infrastructure outputs before Kubernetes implementation. It does not configure Kubernetes/Helm providers or create a namespace, so infrastructure creation cannot accidentally bootstrap the application in the same plan. Supply endpoints from infrastructure outputs after testing private routes; do not invent endpoints or set the verification flag from resource creation alone.

No state-reading permissions are granted to application pods. Future platform jobs receive this small JSON handoff instead of infrastructure state, admin kubeconfig or database passwords. Their remote state belongs to the platform container/key. Azure object IDs used for workload federation stay in the Azure integration layer.