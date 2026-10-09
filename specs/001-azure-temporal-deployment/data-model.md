# Deployment configuration model

This feature adds operational configuration, not application database tables.

EnvironmentProfile -> PlatformOutputs -> ReleaseManifest -> SchemaOperation -> DeploymentRecord -> ReadinessReport.

- EnvironmentProfile is version-controlled without secrets; production profile cannot be marked ready until capacity, availability, recovery and access inputs are resolved.
- PlatformOutputs contain endpoint and secret references only; provider IDs remain in Azure adapters.
- ReleaseManifest is immutable per release and binds commit, binaries, images and schema checksums.
- SchemaOperation records database, before/after version, lock, release, sanitized result and operator identity.
- DeploymentRecord binds manifest digests, chart pin, values checksum and environment.
- ReadinessReport records measured test results and acceptance by the operational owner.

State transitions: draft -> validated -> built -> infrastructure-ready -> schema-ready -> rolled-out -> staging-verified -> operationally-accepted.
Planning artifacts are at draft/validated-document status only. No transition that mutates a cloud service is authorized now.
Failure at any stage blocks dependent transitions; recovery resumes from recorded state rather than deleting durable resources.
