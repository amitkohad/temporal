# Phase 4 — Source build implementation

Date: 2026-10-09. Authoritative branch: `codex/001-azure-temporal-deployment`.

T032–T040 implementation is complete. Source compilation, local image assembly and executable checks succeeded. Real release validation is blocked by unclassified scanner findings; this is not an approved or published release. See T093 for follow-up before T073/T080.

## Implemented feature

- `build-source.sh` verifies the full fork commit, branch/event and source ancestry, exports committed source, verifies Go module locks and compiles both binaries through repository Make targets. Driver hashes captured before compilation must match afterward.
- `deployment-server.Dockerfile` and `sql-tools.Dockerfile` package only compiled binaries and matching schemas on a digest-pinned standard distroless base. UID 1000:1000 and direct entrypoints replace the upstream CLI-downloading admin-tools path for this deployment.
- `build-images.sh` rejects changed/extra artifacts, changed drivers, mutable latest references and unapproved runtime base names. It assembles local images without publication.
- `collect-release-evidence.sh`, `release-manifest.sh` and `validate-release.sh` bind source/build/image metadata, compiled and packaged bytes, schema versions, SBOMs, unsigned provenance and raw scan evidence. Candidates have no registry pull references; published releases additionally require committed drivers and immutable ACR digests.
- Build-only GitHub validation has no Azure credentials or publication. A separate manual release workflow performs build/scan/validation before protected staging OIDC publication, verifies transferred bytes and both image IDs before credentials, refuses content changes to existing tags, verifies remote registry manifests and cleans ephemeral registry credentials.
- The scanner installer checks the pinned official Trivy 0.75.0 archive hash. Unknown severity, malformed evidence, missing bindings, secrets and unapproved HIGH/CRITICAL findings block release. No exception was invented for this candidate.

## Actual build evidence

Application source: `717f485c760d1068aa310906466468e51120254f` from the approved fork. Go 1.27.2, Linux amd64, CGO disabled, disable_grpc_modules and repository Make targets. go.mod/go.sum remained unchanged; module verification passed. Build output contains two binaries and 84 schema files, each hashed.

| Artifact | SHA-256 / local Docker image ID |
|---|---|
| temporal-server binary | b4ac7fe809b0f0eb8715a84e9b4d99a0b0058f2480e796b687a7f56c9e66f46a |
| temporal-sql-tool binary | 9575d4ed5963c125b42521a29290ad733b31e82480249d2ecd0c929fcd07f14c |
| server local image | sha256:7fb0092702190cd4b75e3d849eb8d3c780fb2d72fd122ca8e5fa2642e0be48eb |
| SQL-tools local image | sha256:def23ab532c4d0fe1c1a648469db0172cac4cc3a932cae359b3fb250dd87fb8c |

Both images ran --version successfully and reported 1.33.0 under `--read-only --network none --cap-drop ALL --security-opt no-new-privileges`; SQL help also passed. Metadata reports PostgreSQL persistence 1.19 and visibility 1.14. Docker inspection confirmed UID 1000:1000 and Linux amd64. Actual image binary/schema copies matched source-build hashes before scanning.

The custom local builder ID is `sha256:5ae79b162a43aa510a00b4436fcf68259d132a1f6422e5bd2881251449a5cb62`; its immutable standard Go parent is recorded separately. Build-driver combined hash is `e307bbd7d0fd8eee0bb4ccc099a8f82e80424fcd0a6f1fafc566c78788f8ced0`. Drivers are uncommitted and explicitly marked dirty; committed application source is clean. This local candidate cannot become a published release without reviewed committed drivers on the same branch.

## Real scan outcome and follow-up

Trivy 0.75.0 collected CycloneDX 1.7 SBOMs, provenance and JSON vulnerability/secret/misconfiguration results for both exact local images. Each image has three LOW, three MEDIUM and six UNKNOWN vulnerability findings; no HIGH/CRITICAL severity or secret findings were reported. Image misconfiguration scanning found no config files to inspect, so it is not a Kubernetes policy assessment. Both images share the following unclassified findings:

| Finding | Package / installed version | Scanner-reported fixed version |
|---|---|---|
| DLA-4792-1 | tzdata 2026b-0+deb12u1 | 2026c-0+deb12u1 |
| GO-2026-5932 | golang.org/x/crypto v0.55.0 | None reported |
| CVE-2026-78659 | golang.org/x/net v0.58.0 | 0.60.0 |
| CVE-2026-78660 | golang.org/x/net v0.58.0 | 0.60.0 |
| CVE-2026-78663 | golang.org/x/net v0.58.0 | 0.60.0 |
| CVE-2026-78669 | golang.org/x/net v0.58.0 | 0.60.0 |

These are raw scanner findings, not an assessment of reachable vulnerable code. Review advisory applicability and affected symbols, supported base/dependency fixes and remaining severity uncertainty. GO-2026-5932 concerns deprecated OpenPGP packages with no fixed version; module presence alone does not prove their use by these binaries. Consult the [Go advisory](https://pkg.go.dev/vuln/GO-2026-5932) during reachability review. Do not edit raw scan results, silently exclude findings, downgrade severity or manufacture exceptions to pass the gate. Rebuild a reviewed source/base candidate and regenerate evidence after remediation. The approved baseline and repository dependency locks were preserved in this phase.

Artifacts remain ignored under `.deployment-local/phase4-bundle`; it contains build/evidence for review, not Azure credentials. There is no accepted candidate manifest or published release while the gate rejects these findings. [Build/release runbook](../../docs/deployment/source-build.md) and [evidence contract](../../scripts/deployment/RELEASE-EVIDENCE.md) describe reproduction and later promotion.

## Verification and execution boundary

All 36 deployment helper/policy tests passed after integration corrections (seven migration/archive, four source packaging, 13 release evidence and 12 workflow tests). Fixture tests cover source-only packaging, artifact substitutions, source/schema/image mismatches, malformed severity, exception scope/expiry, candidate versus publication and workflow credential/gate ordering. Linux Bash syntax, workflow YAML/run-step/embedded-Python syntax and whitespace checks are included.

`make lint-code-fast GOLANGCI_LINT_BASE_REV=HEAD` ran in the Linux builder and reported no changed Go packages. No Go source was edited; repository Go tests were not required for this infrastructure/build change.

All compilation and scans used local Docker compute. Azure AKS/PostgreSQL/runner were not restarted, no new Azure resources were needed, and no GitHub workflow was dispatched. No images were pushed, no schema initialized, no Temporal application deployed, and no branch creation, merge or commit occurred.
Real integration corrected CycloneDX 1.7 acceptance and bound Trivy scans to Metadata.ImageID/ArtifactName rather than Trivy internal artifact-cache IDs. Final real validation reached the intended rejection: `Unknown vulnerability severity requires review`. Raw scan results were retained unchanged, and no candidate manifest was created. Deployment shell/Dockerfile LF attributes preserve Linux execution after Windows Git checkout.
