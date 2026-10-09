# Staging recovery decisions

Date: 2026-10-09. Profile: minimum-cost staging, not production.

## Recovery profile
Use PostgreSQL managed backups with seven-day retention and local redundancy initially. Keep both persistence and visibility databases recoverable together. Do not substitute a disposable in-pod PostgreSQL database for managed persistence.
Proposed pilot targets: RPO at most one hour, RTO at most four hours during attended test windows. These are acceptance targets to prove in future isolated restore drills, not verified Azure guarantees or signed production service objectives.
Single-node Temporal and non-HA burstable PostgreSQL may incur outages. Preserve histories and resume workflows after recovery; do not delete databases to make a smoke test pass.
Regional replication, zone-redundant HA and geo-redundant backups are deferred for staging cost. No regional disaster-recovery guarantee applies. Production requires a separately evaluated subscription, HA/DR design and operational acceptance.

## Responsibility model
Platform maintainer owns authorized Azure access and infrastructure recovery; database maintainer owns backup/schema/restore; application maintainer validates resumed workflows. For this personal pilot the human operator is the escalation point; no staffed on-call coverage is assumed.
A named recovery owner, contact and acceptance of RPO/RTO are still required before deployment. No contact, automated paging route or authority is invented from the repository owner name.

## Later restore evidence
Restore to an isolated PostgreSQL server, bind an isolated Temporal cluster using matching source/schema versions, validate workflow histories and visibility, record actual RPO/RTO and protect the original databases. Acquire authorization before creating restore resources or running namespace/schema operations.
Never drop/overwrite the source databases or use Makefile install-schema-postgresql12 on hosted data.
Retain backups/state during cost cleanup; stopped database storage/backups can still be billed. Document auto-restart and lifecycle behavior before adding schedules.

Sources: [PostgreSQL backups and restore](https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/concepts-backup-restore), [PostgreSQL availability](https://learn.microsoft.com/en-us/azure/postgresql/high-availability/concepts-high-availability).
