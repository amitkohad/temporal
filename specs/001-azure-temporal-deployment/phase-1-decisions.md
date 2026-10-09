# Phase 1 decision register

Date: 2026-10-09. Branch: codex/001-azure-temporal-deployment.
Status: five tasks complete; three tasks partially resolved. No infrastructure, images or workflows were deployed.

## User decisions
- Keep all work on codex/001-azure-temporal-deployment; never create another branch or merge to main.
- First environment is a staging pilot.
- Standard toolchain/OS images, managed Azure services and platform agents are allowed; Temporal application binaries remain source-built.
- Minimize cost and use free benefits where actually eligible.
- Basic ACR with an authenticated public endpoint is accepted; Temporal and PostgreSQL remain private.
- Do not impose a spending cap. Report costs without inventing a budget threshold.

## Input/evidence register
| Input | Selection/evidence | State |
|---|---|---|
| Azure scope | Active Visual Studio Enterprise subscription aa228172-c4ae-4c29-bd05-dcdcebb70ff4; tenant 48d2ccb2-9e24-49cc-921b-89962ed5f85f | Observed |
| Resource group | Existing rg-nexusflow; empty inventory; centralindia | Observed; reference-only ownership selected |
| Classification | Staging pilot | User selected |
| Region | Central India, based on existing group and minimum-complexity topology | Selected for pilot |
| Names and CIDRs | environment.md | Selected; ACR/storage available, visible subscription overlap checked |
| Compute | AKS Free, one shared D2s_v5 node; quota 4/20 regional cores in use, DSv5 0/20 | Offering/quota observed; live capacity not guaranteed |
| PostgreSQL | Version 17 candidate, B1ms 32 GiB, no HA | Catalog observed; subscription DB quota still unverified |
| Cost | Core subtotal USD 100.81 always-on or USD 31.28 for 176 compute hours; ancillary charges excluded | Public rate evidence recorded |
| Credit/spending policy | Account name is insufficient; quotaId/spendingLimit null | Unverified; no cap requested |
| Source baseline | 717f485c760d1068aa310906466468e51120254f; metadata 1.33.0, schema 1.19/1.14 | Selected staging baseline; not a production release |
| Go toolchain | Stable 1.27.2 catalogue/digest available; local Go absent | Availability verified; execution deferred |
| Workload targets | Baseline 1 start/sec, 100 open workflows, three-day retention; measured capacity required | Proposed pilot defaults |
| Recovery | Seven-day backups, local redundancy, no regional DR, proposed RPO 1h/RTO 4h | Defaults proposed; owner/acceptance open |
| Connectivity | Private API/database, ephemeral VNet runner, no permanent paid gateway | Design selected; privileges/access not tested |
| TLS/client identity | Issuer and approved clients not supplied | Open |
| Provider registration | Nine core namespaces Registered | Observed; future extras require preflight |

## Task disposition
| Task | Status | Evidence / remaining work |
|---|---|---|
| T001 | Complete | Active account and existing empty group verified; staging/Central India selected; environment.md |
| T002 | Complete | Names/ranges and state isolation selected; ACR/storage name checks and visible VNet overlap review; environment.md |
| T003 | Partial | Compute quota/offerings, provider registrations and retail rates verified; no cap requested. PostgreSQL subscription quota and contradictory regional HA capability response remain unresolved. HA is not enabled for staging. |
| T004 | Complete for Phase 1 selection | Immutable branch baseline and available supported Go patch selected with archive digest; source-build.md. Tool installation and compilation remain later build tasks. |
| T005 | Complete | User accepted source-only boundary; source-build.md |
| T006 | Complete for pilot defaults | Measurable low-load envelope and retention recorded; capacity.md. Actual throughput/SLA claims require later tests. |
| T007 | Partial | Cost-aware backup/DR defaults and owner roles documented; named recovery owner and target acceptance are still required. |
| T008 | Partial | Private runner/DNS/federation topology chosen; bootstrap approver, client identity and certificate authority remain unresolved. |

Complete indicates the Phase 1 decision artifact exists with stated evidence, not that runtime behavior or permissions have been validated. Partial tasks stay unchecked in tasks.md.

## Limits and next gate
No role assignments, provider registrations, installations, Azure logins, account-context changes or resource mutations were performed. Existing CLI login was used read-only.
Resolve the three partial task inputs before declaring Phase 1 complete. Phase 2 contracts can later be developed against selected staging defaults, but no apply is authorized.

Documents: [environment](../../docs/deployment/environment.md), [capacity](../../docs/deployment/capacity.md), [source build](../../docs/deployment/source-build.md), [recovery](../../docs/deployment/recovery.md), [access](../../docs/deployment/access.md).
