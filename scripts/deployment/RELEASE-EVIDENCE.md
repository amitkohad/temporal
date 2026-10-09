# Release evidence contract

Use a bundle root containing `build/` and `evidence/`. Build-source writes `build-metadata.json`; build-images writes `image-metadata.json`. Set TRIVY_VERSION to the exact installed, independently checksum-verified scanner version. The collector downloads scanner vulnerability databases through Trivy; it never downloads Temporal binaries or images.

```
bash scripts/deployment/collect-release-evidence.sh bundle/build bundle/evidence
bash scripts/deployment/release-manifest.sh bundle/build bundle/evidence bundle/candidate.json
bash scripts/deployment/validate-release.sh bundle/candidate.json
```

The collector invokes Trivy against exact local Docker image IDs for CycloneDX SBOMs and vulnerability/secret/misconfiguration scans. It checks architecture, nonroot user and OCI source/revision labels. It binds the SBOM's image component hash to the inspected local Docker ID and writes in-toto SLSA provenance recording commit, build metadata hash, builder and scanner. This is locally generated provenance, not a signed attestation or an assertion of a SLSA assurance level. Trusted protected CI and subsequent registry attestations remain separate controls. The installed scanner version must match TRIVY_VERSION; tool acquisition/version/checksum verification belongs to the workflow.

Release generation checks binary/schema file hashes, both schema versions, clean fork source metadata, two source-built images, digest-pinned standard bases, SBOM subjects, provenance material/subject, and raw scan identity. Missing or mismatched evidence, secrets, unknown severity, and high/critical vulnerabilities fail. HIGH/CRITICAL vulnerability exceptions must bind vulnerability ID, package and exact local image ID plus owner, reason and an unexpired ISO date. Optional evidence/exceptions.json is an array with fields vulnerability_id, package, image_id, owner, reason, expires_on. Misconfiguration or secret findings have no exemption path. A manifest is created exclusively and is never overwritten.

A candidate records local_image_id and leaves registry_reference null. Local Docker image IDs are not OCI manifest pull digests. To create a separate published manifest after authorized registry push and independent digest inspection, supply --published publication.json:

```
{
  "source_commit": "FULL_40_HEX_COMMIT",
  "images": {
    "server": {"local_image_id": "sha256:CONFIG_DIGEST", "registry_reference": "REGISTRY.azurecr.io/nexusflow/temporal-server@sha256:OCI_DIGEST"},
    "sql-tools": {"local_image_id": "sha256:CONFIG_DIGEST", "registry_reference": "REGISTRY.azurecr.io/nexusflow/temporal-sql-tools@sha256:OCI_DIGEST"}
  }
}
```

Run validate-release.sh published.json --require-published before consuming release references. The manifest helper verifies the publication binding and syntax; the publish workflow must verify the actual registry digest. No helper here authenticates to Azure, pushes an image, initializes schemas or deploys pods. All evidence and artifact files must accompany the manifest because validation recalculates their hashes. Restrict access to scan/build bundles and never include credentials.

Offline fixture checks: python -m unittest discover -s scripts/deployment/tests -p test_release_evidence.py. Passing fixture tests prove validation behavior, not a real source build, image scan or publication.