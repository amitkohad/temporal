#!/usr/bin/env python3
"""Bind source-build artifacts to independently collected release evidence."""
import argparse
import datetime as dt
import hashlib
import json
import re
import sys
import os
import subprocess
import tempfile
from pathlib import Path

REPOSITORY = "https://github.com/amitkohad/temporal"
DIGEST = re.compile(r"sha256:[0-9a-f]{64}")
COMMIT = re.compile(r"[0-9a-f]{40}")
IMAGES = ("server", "sql-tools")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load(path):
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def checksum(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def artifact(root, item):
    path = (root / item["path"]).resolve()
    require(path.is_relative_to(root.resolve()) and path.is_file(), "Artifact path escapes bundle or is missing")
    require(checksum(path) == item["sha256"], "Artifact checksum mismatch")
    return path


def check_exception(exception, vulnerability, image, today):
    return (exception.get("vulnerability_id") == vulnerability.get("VulnerabilityID")
            and exception.get("package") == vulnerability.get("PkgName")
            and exception.get("image_id") == image
            and isinstance(exception.get("owner"), str) and bool(exception["owner"].strip())
            and isinstance(exception.get("reason"), str) and bool(exception["reason"].strip())
            and dt.date.fromisoformat(exception["expires_on"]) >= today)


def check_scan(scan, image, exceptions, today):
    require(scan.get("SchemaVersion") == 2 and DIGEST.fullmatch(scan.get("ArtifactID", "")),
            "Scan must use Trivy schema 2 and a valid internal artifact digest")
    require(scan.get("ArtifactName") == image and scan.get("Metadata", {}).get("ImageID") == image,
            "Scan metadata must bind the exact local image ID")
    require(scan.get("ArtifactType") == "container_image" and isinstance(scan.get("Results"), list),
            "Container scan results are missing")
    require(scan.get("Results"), "Empty scan evidence is not accepted")
    for result in scan["Results"]:
        require(result.get("Class") in ("os-pkgs", "lang-pkgs", "secret", "config"), "Unrecognized scan result class")
        for issue in result.get("Vulnerabilities", []):
            severity = issue.get("Severity", "UNKNOWN").upper()
            require(severity in ("LOW", "MEDIUM", "HIGH", "CRITICAL"), "Unknown vulnerability severity requires review")
            if severity in ("HIGH", "CRITICAL"):
                require(any(check_exception(e, issue, image, today) for e in exceptions),
                        "Unapproved high/critical vulnerability: " + issue.get("VulnerabilityID", "missing ID"))
        require(not result.get("Secrets"), "Image contains detected secrets")
        for issue in result.get("Misconfigurations", []):
            require(issue.get("Severity", "UNKNOWN").upper() in ("LOW", "MEDIUM"),
                    "Blocking image misconfiguration")


def check_evidence(root, image, commit, exceptions, today, build_hash):
    sbom = load(artifact(root, image["sbom"]))
    require(sbom.get("bomFormat") == "CycloneDX" and sbom.get("specVersion") in ("1.5", "1.6", "1.7"),
            "CycloneDX SBOM is required")
    require(isinstance(sbom.get("components"), list) and sbom["components"], "SBOM components are missing")
    hashes = sbom.get("metadata", {}).get("component", {}).get("hashes", [])
    require(any(h.get("alg") == "SHA-256" and h.get("content") == image["local_image_id"][7:] for h in hashes),
            "SBOM is not bound to the local image ID")
    provenance = load(artifact(root, image["provenance"]))
    require(provenance.get("_type") == "https://in-toto.io/Statement/v1"
            and provenance.get("predicateType") == "https://slsa.dev/provenance/v1", "SLSA provenance statement is required")
    require(any(s.get("digest", {}).get("sha256") == image["local_image_id"][7:]
                for s in provenance.get("subject", [])), "Provenance subject mismatch")
    definition = provenance.get("predicate", {}).get("buildDefinition", {})
    require(any(m.get("uri") == REPOSITORY and m.get("digest", {}).get("gitCommit") == commit
                for m in definition.get("resolvedDependencies", [])), "Provenance source commit mismatch")
    require(definition.get("buildType") == REPOSITORY + "/source-build/v1", "Unapproved build type")
    require(provenance.get("predicate", {}).get("runDetails", {}).get("builder", {}).get("id"),
            "Provenance builder identity is required")
    require(any(item.get("name") == "build-metadata" and item.get("digest", {}).get("sha256") == build_hash
                for item in provenance.get("predicate", {}).get("runDetails", {}).get("byproducts", [])),
            "Provenance build metadata checksum mismatch")
    check_scan(load(artifact(root, image["scan"])), image["local_image_id"], exceptions, today)


def validate(manifest, root, published=False, today=None):
    today = today or dt.datetime.now(dt.timezone.utc).date()
    require(manifest.get("schema_version") == 1, "Unsupported release schema")
    source = manifest["source"]
    require(source.get("repository") == REPOSITORY and COMMIT.fullmatch(source.get("commit", "")),
            "Release requires approved fork and full source commit")
    require(source.get("dirty") is False, "Release source must be clean")
    require(manifest.get("status") in ("candidate", "published"), "Invalid release state")
    require(set(manifest["images"]) == set(IMAGES), "Exactly server and sql-tools images are required")
    require(set(manifest["binaries"]) == {"temporal-server", "temporal-sql-tool"}, "Source-built binaries are missing")
    for item in manifest["binaries"].values():
        artifact(root, item)
    schemas = manifest["schemas"]
    require(schemas.get("persistence_version") and schemas.get("visibility_version") and schemas.get("files"),
            "Both matching schema versions and files are required")
    for item in schemas["files"]:
        artifact(root, item)
    require("build_metadata" in manifest, "Build metadata evidence is required")
    metadata_path = artifact(root, manifest["build_metadata"])
    metadata = load(metadata_path)
    require(metadata.get("source_commit") == source["commit"] and metadata.get("source_dirty") is False, "Build metadata source mismatch")
    require(metadata.get("toolchain") == "go1.27.2" and metadata.get("platform") == "linux/amd64", "Build toolchain/platform mismatch")
    require(metadata.get("build_flags", {}).get("CGO_ENABLED") == "0" and set(metadata.get("build_flags", {}).get("make_targets", [])) == {"temporal-server", "temporal-sql-tool"}, "Build flags/targets mismatch")
    if metadata.get("builder_image") is not None:
        require(DIGEST.fullmatch(metadata["builder_image"]) and re.fullmatch(r"[^\s@]+@sha256:[0-9a-f]{64}", metadata.get("builder_parent_image", "")), "Container builder image/parent pins are required")
    if manifest["status"] == "published" or published:
        require(metadata.get("build_driver", {}).get("dirty") is False, "Published release requires committed build drivers")
    require(metadata.get("schema_versions") == {"persistence": schemas["persistence_version"], "visibility": schemas["visibility_version"]}, "Build schema versions mismatch")
    expected_files = {str((metadata_path.parent / path).resolve().relative_to(root.resolve())).replace("\\", "/"): digest
                      for path, digest in metadata["files"].items()}
    represented_files = {item["path"]: item["sha256"] for item in list(manifest["binaries"].values()) + schemas["files"]}
    require(represented_files == expected_files, "Manifest artifact inventory differs from build metadata")
    for name, item in manifest["binaries"].items():
        require(Path(item["path"]).name == name, "Binary name/path mismatch")
    require(manifest.get("server_version") == metadata.get("server_version"), "Server version mismatch")
    image_metadata = load(artifact(root, manifest["image_metadata"]))
    require(image_metadata.get("source_commit") == source["commit"], "Image metadata source mismatch")
    for name, key in (("server", "server"), ("sql-tools", "sql_tools")):
        image = manifest["images"][name]
        require(image["local_image_id"] == image_metadata["images"][key]["image_id"]
                and image["base_images"] == [image_metadata["runtime_base"]], "Image metadata binding mismatch")
    exceptions = manifest.get("vulnerability_exceptions", [])
    for exception in exceptions:
        require(dt.date.fromisoformat(exception["expires_on"]) >= today, "Expired vulnerability exception")
    for name, image in manifest["images"].items():
        require(DIGEST.fullmatch(image.get("local_image_id", "")), "Immutable local image ID is required")
        require(image.get("source_commit") == source["commit"] and image.get("source_built") is True,
                "Image source provenance mismatch")
        require(image.get("runtime_user") == "1000" and image.get("architecture") == "linux/amd64", "Image hardening mismatch")
        require(len(image.get("base_images", [])) == 1 and re.fullmatch(
                    r"gcr\.io/distroless/static-debian12:nonroot@sha256:[0-9a-f]{64}", image["base_images"][0]),
                "Runtime base must be approved digest-pinned distroless static-debian12 nonroot")
        check_evidence(root, image, source["commit"], exceptions, today, manifest["build_metadata"]["sha256"])
        reference = image.get("registry_reference")
        if manifest["status"] == "published" or published:
            require(reference and re.fullmatch(r"[a-z0-9.-]+\.azurecr\.io/nexusflow/temporal-" + name + r"@sha256:[0-9a-f]{64}", reference),
                    "Published release requires an immutable ACR manifest digest")
        else:
            require(reference is None, "Candidate must not claim a registry pull digest")
    require(not published or manifest["status"] == "published", "A candidate cannot be deployed")
    return manifest


def create(build_dir, evidence_dir, output, publication=None):
    metadata = load(build_dir / "build-metadata.json")
    image_metadata = load(build_dir / "image-metadata.json")
    require(metadata["source_commit"] == image_metadata["source_commit"], "Build/image commit mismatch")
    files = metadata["files"]
    binary_paths = {name: next((path for path in files if Path(path).name == name), None)
                    for name in ("temporal-server", "temporal-sql-tool")}
    require(all(binary_paths.values()), "Build metadata must include both compiled binaries")
    build = {
        "source": {"repository": metadata["source_repository"], "commit": metadata["source_commit"], "dirty": metadata.get("source_dirty")},
        "binaries": {name: {"path": path, "sha256": files[path]} for name, path in binary_paths.items()},
        "schemas": {"persistence_version": metadata["schema_versions"]["persistence"],
                    "visibility_version": metadata["schema_versions"]["visibility"],
                    "files": [{"path": path, "sha256": digest} for path, digest in files.items() if path.startswith("schema/")]},
        "images": {name: {"local_image_id": image_metadata["images"][key]["image_id"],
                          "source_commit": metadata["source_commit"], "source_built": True,
                          "runtime_user": "1000", "architecture": metadata["platform"],
                          "base_images": [image_metadata["runtime_base"]]}
                   for name, key in (("server", "server"), ("sql-tools", "sql_tools"))},
    }
    root = output.parent.resolve()
    require(build_dir.resolve().is_relative_to(root) and evidence_dir.resolve().is_relative_to(root),
            "Output must be at bundle root containing build and evidence directories")
    manifest = {"schema_version": 1, "status": "candidate", "source": build["source"],
                "binaries": build["binaries"], "schemas": build["schemas"], "images": build["images"],
                "vulnerability_exceptions": load(evidence_dir / "exceptions.json") if (evidence_dir / "exceptions.json").exists() else []}
    for item in list(manifest["binaries"].values()) + manifest["schemas"]["files"]:
        item["path"] = str((build_dir / item["path"]).resolve().relative_to(root)).replace("\\", "/")
    for name, image in manifest["images"].items():
        for key in ("sbom", "provenance", "scan"):
            path = evidence_dir / (name + "." + key + ".json")
            image[key] = {"path": str(path.resolve().relative_to(root)).replace("\\", "/"), "sha256": checksum(path)}
        image["registry_reference"] = None
    if publication:
        require(publication["source_commit"] == manifest["source"]["commit"], "Publication source mismatch")
        require(set(publication["images"]) == set(IMAGES), "Publication must include both images")
        for name, image in manifest["images"].items():
            require(publication["images"][name]["local_image_id"] == image["local_image_id"], "Publication image mismatch")
            image["registry_reference"] = publication["images"][name]["registry_reference"]
        manifest["status"] = "published"
    manifest["build_metadata"] = {"path": str((build_dir / "build-metadata.json").resolve().relative_to(root)).replace("\\", "/"), "sha256": checksum(build_dir / "build-metadata.json")}
    manifest["image_metadata"] = {"path": str((build_dir / "image-metadata.json").resolve().relative_to(root)).replace("\\", "/"), "sha256": checksum(build_dir / "image-metadata.json")}
    manifest["server_version"] = metadata["server_version"]
    validate(manifest, root)
    encoded = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    with output.open("x", encoding="utf-8") as stream:
        stream.write(encoded)
    return checksum(output)



def collect(build_dir, evidence_dir):
    metadata = load(build_dir / "build-metadata.json")
    images = load(build_dir / "image-metadata.json")
    require(metadata["source_commit"] == images["source_commit"], "Build/image commit mismatch")
    expected = os.environ.get("TRIVY_VERSION", "")
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", expected), "TRIVY_VERSION must pin the installed scanner")
    actual = json.loads(subprocess.check_output(["trivy", "version", "--format", "json"], text=True))
    require(actual.get("Version") == expected, "Installed scanner version mismatch")
    evidence_dir.mkdir(parents=True, exist_ok=False)
    for name, key in (("server", "server"), ("sql-tools", "sql_tools")):
        image = images["images"][key]["image_id"]
        require(DIGEST.fullmatch(image), "Local image ID missing")
        inspect = json.loads(subprocess.check_output(["docker", "image", "inspect", image], text=True))[0]
        require(inspect["Id"] == image and inspect["Config"]["User"] == "1000:1000"
                and inspect["Architecture"] == "amd64" and inspect["Os"] == "linux", "Built image hardening mismatch")
        container = subprocess.check_output(["docker", "create", image], text=True).strip()
        try:
            with tempfile.TemporaryDirectory() as temporary:
                extracted = Path(temporary)
                binary = "temporal-server" if name == "server" else "temporal-sql-tool"
                subprocess.run(["docker", "cp", container + ":/usr/local/bin/" + binary, str(extracted / binary)], check=True)
                require(checksum(extracted / binary) == metadata["files"]["bin/" + binary], "Image binary differs from source build")
                if name == "sql-tools":
                    subprocess.run(["docker", "cp", container + ":/etc/temporal/schema", str(extracted / "schema")], check=True)
                    for path, digest in metadata["files"].items():
                        if path.startswith("schema/"):
                            require(checksum(extracted / path) == digest, "Packaged schema differs from source build")
        finally:
            subprocess.run(["docker", "rm", container], check=True, stdout=subprocess.DEVNULL)
        labels = inspect["Config"].get("Labels") or {}
        require(labels.get("org.opencontainers.image.source") == REPOSITORY, "Image source label mismatch")
        require(labels.get("org.opencontainers.image.revision") == metadata["source_commit"], "Image revision label mismatch")
        require(labels.get("io.nexusflow.build.driver.sha256") == metadata["build_driver"]["sha256"], "Image driver label mismatch")
        for kind, arguments in (("sbom", ["--format", "cyclonedx"]),
                                ("scan", ["--format", "json", "--scanners", "vuln,secret,misconfig"])):
            path = evidence_dir / (name + "." + kind + ".json")
            subprocess.run(["trivy", "image", "--image-src", "docker", "--timeout", "15m", *arguments,
                            "--output", str(path), image], check=True)
        sbom_path = evidence_dir / (name + ".sbom.json")
        sbom = load(sbom_path)
        component = sbom.setdefault("metadata", {}).setdefault("component", {})
        component["hashes"] = [{"alg": "SHA-256", "content": image[7:]}]
        sbom_path.write_text(json.dumps(sbom, indent=2) + "\n", encoding="utf-8")
        provenance = {
            "_type": "https://in-toto.io/Statement/v1", "predicateType": "https://slsa.dev/provenance/v1",
            "subject": [{"name": name, "digest": {"sha256": image[7:]}}],
            "predicate": {
                "buildDefinition": {"buildType": REPOSITORY + "/source-build/v1",
                    "externalParameters": {"platform": metadata["platform"], "toolchain": metadata["toolchain"]},
                    "resolvedDependencies": [{"uri": REPOSITORY, "digest": {"gitCommit": metadata["source_commit"]}}]},
                "runDetails": {"builder": {"id": os.environ.get("RELEASE_BUILDER_ID", "local/source-build")},
                    "metadata": {"invocationId": os.environ.get("GITHUB_RUN_ID", "attended-local")},
                    "byproducts": [{"name": "build-metadata", "digest": {"sha256": checksum(build_dir / "build-metadata.json")}},
                                   {"name": "scanner", "content": {"name": "Trivy", "version": expected}}]},
            },
        }
        (evidence_dir / (name + ".provenance.json")).write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")

def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    generate = sub.add_parser("create")
    generate.add_argument("build_dir", type=Path)
    generate.add_argument("evidence_dir", type=Path)
    generate.add_argument("output", type=Path)
    generate.add_argument("--published", type=Path)
    collector = sub.add_parser("collect")
    collector.add_argument("build_dir", type=Path)
    collector.add_argument("evidence_dir", type=Path)
    check = sub.add_parser("validate")
    check.add_argument("manifest", type=Path)
    check.add_argument("--require-published", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "create":
            print("Manifest SHA-256: " + create(args.build_dir, args.evidence_dir, args.output,
                  load(args.published) if args.published else None))
        elif args.command == "collect":
            collect(args.build_dir, args.evidence_dir)
            print("Release evidence collected; candidate validation is still required")
        else:
            validate(load(args.manifest), args.manifest.parent, args.require_published)
            print("Release evidence verified: " + checksum(args.manifest))
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print("Release rejected: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())