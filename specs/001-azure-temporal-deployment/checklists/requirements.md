# Specification review checklist

- [x] User-selected Azure, managed Kubernetes, PostgreSQL, source builds and rg-nexusflow are recorded.
- [x] No existing AKS or ACR is assumed.
- [x] User stories have priorities, independent tests and acceptance scenarios.
- [x] Functional requirements and measurable success criteria are identified.
- [x] Terraform portability is bounded honestly; Azure-specific resources remain in adapters.
- [x] Resource-group ownership and AKS-managed node-group exception are recorded.
- [x] Source-only CLI download conflict and destructive Makefile schema setup are identified.
- [x] Bootstrap state, private runners, DNS, identity, security and secret lifecycle are covered.
- [x] Durability, visibility, capacity, recovery, upgrades and operational handover are covered.
- [x] Implementation and execution-only activities have separate gates.
- [x] All functional requirements map to tasks.
- [x] Repository-specific evidence and external source links are recorded.
- [ ] Resolve environment inputs and compatibility pins before implementation/execution dependencies.
- [ ] Confirm toolchain/base-image/managed-service source-only boundary.
- [ ] Accept sizing, availability, budget, recovery and operational ownership.
- [ ] Complete implementation and static/staging validation in later work.
- [ ] Authorize deployment separately.

Checked items denote document coverage, not completed infrastructure or runtime validation.
