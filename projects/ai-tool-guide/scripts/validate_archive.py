from __future__ import annotations

import csv
import hashlib
import json
import re
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = PROJECT_ROOT.parents[1]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    results: list[tuple[str, bool, str]] = []

    def check(name: str, condition: bool, evidence: str) -> None:
        results.append((name, bool(condition), evidence))

    zh = PROJECT_ROOT / "README.md"
    en = PROJECT_ROOT / "README.en.md"
    mav = REPO_ROOT / "skills" / "codex" / "mav-slide-craft-skill"
    plugin = REPO_ROOT / "skills" / "plugins" / "hyperframes" / "0.1.2"
    manifest = PROJECT_ROOT / "artifacts" / "source_manifest.csv"

    check("bilingual_pages", zh.is_file() and en.is_file(), "README.md and README.en.md exist")
    check("mav_skill_entrypoint", (mav / "SKILL.md").is_file(), "mav SKILL.md exists")
    check("mav_readme", (mav / "README.md").is_file(), "mav README.md exists")
    check("hyperframes_manifest", (plugin / ".codex-plugin" / "plugin.json").is_file(), "plugin.json exists")
    check("hyperframes_readme", (plugin / "README.md").is_file(), "HyperFrames README.md exists")

    manifest_data = json.loads((plugin / ".codex-plugin" / "plugin.json").read_text(encoding="utf-8"))
    check("plugin_version", manifest_data.get("version") == "0.1.2", "plugin.json version is 0.1.2")
    expected_skills = {"hyperframes", "hyperframes-cli", "hyperframes-registry", "gsap", "website-to-hyperframes"}
    actual_skills = {path.name for path in (plugin / "skills").iterdir() if path.is_dir()}
    check("five_plugin_skills", actual_skills == expected_skills, f"skills={','.join(sorted(actual_skills))}")
    check("plugin_file_count", len([path for path in plugin.rglob("*") if path.is_file()]) == 69, "69 files")

    docs = zh.read_text(encoding="utf-8") + "\n" + en.read_text(encoding="utf-8")
    local_path_pattern = re.compile(r"[A-Za-z]:[\\/](?:Users|Documents)[\\/]", re.IGNORECASE)
    check("no_local_absolute_paths", not local_path_pattern.search(docs), "No user-local absolute path in project pages")
    check("repo_relative_paths", "skills/codex/mav-slide-craft-skill/" in docs and "skills/plugins/hyperframes/0.1.2/" in docs, "Both snapshots are referenced by repository-relative path")

    hashes: dict[str, str] = {}
    with manifest.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            hashes[row["asset"]] = row["sha256"].lower()
    expected_hashes = {
        "user_note": sha256(PROJECT_ROOT / "artifacts" / "source-zh" / "mav-slidecraft与hyperframes说明.md"),
        "mav_skill_definition": sha256(mav / "SKILL.md"),
        "mav_readme": sha256(mav / "README.md"),
        "hyperframes_plugin_manifest": sha256(plugin / ".codex-plugin" / "plugin.json"),
        "hyperframes_plugin_readme": sha256(plugin / "README.md"),
    }
    hash_ok = all(hashes.get(name) == value for name, value in expected_hashes.items())
    check("manifest_hashes", hash_ok, "Key-file hashes match source_manifest.csv")

    credential_pattern = re.compile(
        r"(?i)(?:api[_-]?key|password|secret|token)\s*[:=]\s*[^\s`]+|"
        r"(?:AKIA[0-9A-Z]{16}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,})"
    )
    check("no_plaintext_credentials", not credential_pattern.search(docs), "No common credential pattern in project pages")

    passed = sum(ok for _, ok, _ in results)
    for name, ok, evidence in results:
        print(f"{'PASS' if ok else 'FAIL'} {name}: {evidence}")
    print(f"SUMMARY {passed}/{len(results)} passed; {len(results) - passed} failed")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
