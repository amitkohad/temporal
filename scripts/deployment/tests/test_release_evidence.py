import copy
import datetime as dt
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "release-evidence.py"
SPEC = importlib.util.spec_from_file_location("release_evidence", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ReleaseEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.commit = "a" * 40
        self.image = "sha256:" + "b" * 64
        self.today = dt.date(2026, 10, 9)
        self.manifest = {
            "schema_version": 1, "status": "candidate",
            "source": {"repository": MODULE.REPOSITORY, "commit": self.commit, "dirty": False},
            "binaries": {name: self.write(name, b"compiled-fixture") for name in ("temporal-server", "temporal-sql-tool")},
            "schemas": {"persistence_version": "1.19", "visibility_version": "1.14",
                        "files": [self.write("schema.sql", b"schema-fixture")]},
            "images": {}, "vulnerability_exceptions": [],
        }
        self.manifest["build_metadata"] = self.write("build-metadata.json", json.dumps({"source_commit": self.commit, "source_dirty": False, "toolchain": "go1.27.2", "platform": "linux/amd64", "build_flags": {"CGO_ENABLED": "0", "make_targets": ["temporal-server", "temporal-sql-tool"]}, "build_driver": {"dirty": False}, "server_version": "1.33.0", "files": {item["path"]: item["sha256"] for item in list(self.manifest["binaries"].values()) + self.manifest["schemas"]["files"]}, "schema_versions": {"persistence": "1.19", "visibility": "1.14"}}).encode())
        for name in MODULE.IMAGES:
            sbom = {"bomFormat": "CycloneDX", "specVersion": "1.6", "components": [{"name": "fixture-package"}],
                    "metadata": {"component": {"hashes": [{"alg": "SHA-256", "content": self.image[7:]}]}}}
            provenance = {"_type": "https://in-toto.io/Statement/v1", "predicateType": "https://slsa.dev/provenance/v1",
                          "subject": [{"digest": {"sha256": self.image[7:]}}],
                          "predicate": {"buildDefinition": {"buildType": MODULE.REPOSITORY + "/source-build/v1",
                            "resolvedDependencies": [{"uri": MODULE.REPOSITORY, "digest": {"gitCommit": self.commit}}]},
                            "runDetails": {"builder": {"id": "fixture-builder"}, "byproducts": [{"name": "build-metadata", "digest": {"sha256": self.manifest["build_metadata"]["sha256"]}}]}}}
            scan = {"SchemaVersion": 2, "ArtifactID": "sha256:" + "d" * 64, "ArtifactName": self.image, "Metadata": {"ImageID": self.image}, "ArtifactType": "container_image",
                    "Results": [{"Class": "os-pkgs", "Vulnerabilities": []}]}
            self.manifest["images"][name] = {
                "local_image_id": self.image, "source_commit": self.commit, "source_built": True,
                "runtime_user": "1000", "architecture": "linux/amd64",
                "base_images": ["gcr.io/distroless/static-debian12:nonroot@sha256:" + "c" * 64], "registry_reference": None,
                "sbom": self.write(name + ".sbom.json", json.dumps(sbom).encode()),
                "provenance": self.write(name + ".provenance.json", json.dumps(provenance).encode()),
                "scan": self.write(name + ".scan.json", json.dumps(scan).encode()),
            }

        self.manifest["server_version"] = "1.33.0"
        self.manifest["image_metadata"] = self.write("image-metadata.json", json.dumps({
            "source_commit": self.commit, "runtime_base": "gcr.io/distroless/static-debian12:nonroot@sha256:" + "c" * 64,
            "images": {"server": {"image_id": self.image}, "sql_tools": {"image_id": self.image}}}).encode())

    def write(self, name, content):
        path = self.root / name
        path.write_bytes(content)
        return {"path": name, "sha256": MODULE.checksum(path)}

    def validate(self, manifest=None, published=False):
        return MODULE.validate(manifest or self.manifest, self.root, published, self.today)

    def test_candidate_cannot_be_deployed(self):
        self.assertEqual(self.validate(), self.manifest)
        with self.assertRaisesRegex(ValueError, "immutable ACR"):
            self.validate(published=True)

    def test_release_rejects_mutated_artifact(self):
        (self.root / "temporal-server").write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            self.validate()

    def test_policy_negative_cases(self):
        cases = {
            "wrong repository": lambda m: m["source"].update(repository="https://github.com/temporalio/temporal"),
            "mutable commit": lambda m: m["source"].update(commit="main"),
            "dirty source": lambda m: m["source"].update(dirty=True),
            "root runtime": lambda m: m["images"]["server"].update(runtime_user="0"),
            "prebuilt temporal": lambda m: m["images"]["server"].update(base_images=["temporalio/server@sha256:" + "c" * 64]),
            "latest base": lambda m: m["images"]["server"].update(base_images=["alpine:latest"]),
            "source mismatch": lambda m: m["images"]["server"].update(source_commit="d" * 40),
            "missing schemas": lambda m: m["schemas"].update(files=[]),
            "path escape": lambda m: m["binaries"]["temporal-server"].update(path="../outside"),
        }
        for name, mutate in cases.items():
            with self.subTest(name=name):
                manifest = copy.deepcopy(self.manifest)
                mutate(manifest)
                with self.assertRaises(ValueError):
                    self.validate(manifest)

    def test_missing_or_mismatched_evidence_rejected(self):
        for name in ("sbom", "provenance", "scan"):
            with self.subTest(name=name):
                manifest = copy.deepcopy(self.manifest)
                manifest["images"]["server"][name] = self.write("bad-" + name + ".json", b"{}")
                with self.assertRaises(ValueError):
                    self.validate(manifest)

    def test_rehashed_manifest_cannot_substitute_build_artifact(self):
        self.manifest["binaries"]["temporal-server"] = self.write("temporal-server", b"rehashed-tampered")
        with self.assertRaisesRegex(ValueError, "inventory differs"):
            self.validate()

    def test_image_and_provenance_metadata_must_cross_bind(self):
        original = copy.deepcopy(self.manifest)
        self.manifest["images"]["server"]["local_image_id"] = "sha256:" + "f" * 64
        with self.assertRaisesRegex(ValueError, "metadata binding"):
            self.validate()
        self.manifest = original
        path = self.root / self.manifest["images"]["server"]["provenance"]["path"]
        evidence = json.loads(path.read_text())
        evidence["predicate"]["runDetails"]["byproducts"][0]["digest"]["sha256"] = "f" * 64
        self.manifest["images"]["server"]["provenance"] = self.write(path.name, json.dumps(evidence).encode())
        with self.assertRaisesRegex(ValueError, "build metadata checksum"):
            self.validate()

    def test_dirty_driver_blocks_publication_only(self):
        path = self.root / "build-metadata.json"
        metadata = json.loads(path.read_text())
        metadata["build_driver"]["dirty"] = True
        self.manifest["build_metadata"] = self.write(path.name, json.dumps(metadata).encode())
        for image in self.manifest["images"].values():
            path = self.root / image["provenance"]["path"]
            evidence = json.loads(path.read_text())
            evidence["predicate"]["runDetails"]["byproducts"][0]["digest"]["sha256"] = self.manifest["build_metadata"]["sha256"]
            image["provenance"] = self.write(path.name, json.dumps(evidence).encode())
        self.validate()
        self.manifest["status"] = "published"
        with self.assertRaisesRegex(ValueError, "committed build drivers"):
            self.validate()

    def test_unrecognized_scan_severity_is_rejected(self):
        for severity in ("SEVERE", "", "UNKNOWN"):
            with self.subTest(kind="vulnerability", severity=severity):
                scan = {"SchemaVersion": 2, "ArtifactID": "sha256:" + "d" * 64, "ArtifactName": self.image, "Metadata": {"ImageID": self.image}, "ArtifactType": "container_image",
                        "Results": [{"Class": "os-pkgs", "Vulnerabilities": [{"Severity": severity}]}]}
                with self.assertRaisesRegex(ValueError, "severity requires review"):
                    MODULE.check_scan(scan, self.image, [], self.today)
            with self.subTest(kind="misconfiguration", severity=severity):
                scan = {"SchemaVersion": 2, "ArtifactID": "sha256:" + "d" * 64, "ArtifactName": self.image, "Metadata": {"ImageID": self.image}, "ArtifactType": "container_image",
                        "Results": [{"Class": "config", "Misconfigurations": [{"Severity": severity}]}]}
                with self.assertRaisesRegex(ValueError, "Blocking image misconfiguration"):
                    MODULE.check_scan(scan, self.image, [], self.today)

    def test_unapproved_application_runtime_base_rejected(self):
        for base in ("myregistry.example/temporal-base", "myregistry.example/unrelated-app", "alpine"):
            with self.subTest(base=base):
                manifest = copy.deepcopy(self.manifest)
                reference = base + "@sha256:" + "c" * 64
                for image in manifest["images"].values():
                    image["base_images"] = [reference]
                metadata = json.loads((self.root / "image-metadata.json").read_text())
                metadata["runtime_base"] = reference
                manifest["image_metadata"] = self.write("unapproved-image-metadata.json", json.dumps(metadata).encode())
                with self.assertRaisesRegex(ValueError, "approved digest-pinned"):
                    self.validate(manifest)

    def test_trivy_cyclonedx_17_supported(self):
        for image in self.manifest["images"].values():
            path = self.root / image["sbom"]["path"]
            sbom = json.loads(path.read_text())
            sbom["specVersion"] = "1.7"
            image["sbom"] = self.write(path.name, json.dumps(sbom).encode())
        self.validate()
        scan = {"SchemaVersion": 2, "ArtifactID": "sha256:" + "d" * 64, "ArtifactName": self.image, "Metadata": {"ImageID": self.image}, "ArtifactType": "container_image",
                "Results": [{"Class": "os-pkgs", "Vulnerabilities": [
                    {"VulnerabilityID": "fixture-unrated", "PkgName": "fixture", "Severity": "UNKNOWN"}]}]}
        self.manifest["images"]["server"]["scan"] = self.write("unknown.scan.json", json.dumps(scan).encode())
        with self.assertRaisesRegex(ValueError, "vulnerability severity"):
            self.validate()

    def test_scan_image_binding_uses_metadata_not_internal_cache_digest(self):
        self.validate()
        path = self.root / self.manifest["images"]["server"]["scan"]["path"]
        scan = json.loads(path.read_text())
        self.assertNotEqual(scan["ArtifactID"], self.image)
        for field in ("ImageID", "ArtifactName"):
            with self.subTest(field=field):
                changed = copy.deepcopy(scan)
                if field == "ImageID":
                    changed["Metadata"]["ImageID"] = "sha256:" + "f" * 64
                else:
                    changed["ArtifactName"] = "sha256:" + "f" * 64
                manifest = copy.deepcopy(self.manifest)
                manifest["images"]["server"]["scan"] = self.write("wrong-image.scan.json", json.dumps(changed).encode())
                with self.assertRaisesRegex(ValueError, "exact local image ID"):
                    self.validate(manifest)

    def test_scan_requires_scoped_unexpired_exception(self):
        issue = {"VulnerabilityID": "CVE-fixture", "PkgName": "fixture", "Severity": "HIGH"}
        scan = {"SchemaVersion": 2, "ArtifactID": "sha256:" + "d" * 64, "ArtifactName": self.image, "Metadata": {"ImageID": self.image}, "ArtifactType": "container_image",
                "Results": [{"Class": "os-pkgs", "Vulnerabilities": [issue]}]}
        self.manifest["images"]["server"]["scan"] = self.write("high.scan.json", json.dumps(scan).encode())
        with self.assertRaisesRegex(ValueError, "Unapproved"):
            self.validate()
        exception = {"vulnerability_id": "CVE-fixture", "package": "fixture", "image_id": self.image,
                     "owner": "security-owner", "reason": "documented fixture only", "expires_on": "2026-10-10"}
        self.manifest["vulnerability_exceptions"] = [exception]
        self.validate()
        exception["expires_on"] = "2026-10-08"
        with self.assertRaisesRegex(ValueError, "Expired"):
            self.validate()

    def test_published_digests_are_distinct_from_local_ids(self):
        self.manifest["status"] = "published"
        for name, image in self.manifest["images"].items():
            image["registry_reference"] = "acrnexusflow.azurecr.io/nexusflow/temporal-" + name + "@sha256:" + "e" * 64
        self.validate(published=True)
        self.manifest["images"]["server"]["registry_reference"] = "acrnexusflow.azurecr.io/nexusflow/temporal-server:latest"
        with self.assertRaisesRegex(ValueError, "immutable ACR"):
            self.validate(published=True)


if __name__ == "__main__":
    unittest.main()