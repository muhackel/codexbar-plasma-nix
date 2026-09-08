#!/usr/bin/env python3

import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


CLI_HASH = "sha256-" + "A" * 43 + "="
PLASMA_HASH = "sha256-" + "B" * 43 + "="
OLD_CLI_HASH = "sha256-" + "C" * 43 + "="
OLD_PLASMA_HASH = "sha256-" + "D" * 43 + "="

BASE_SOURCES = {
    "codexbar-cli": {
        "owner": "steipete",
        "repo": "CodexBar",
        "version": "0.56.3",
        "asset": "CodexBarCLI-v0.56.3-linux-x86_64.tar.gz",
        "hash": OLD_CLI_HASH,
    },
    "codexbar-plasma": {
        "owner": "Lucenx9",
        "repo": "codexbar-plasma",
        "version": "0.2.24",
        "hash": OLD_PLASMA_HASH,
    },
}


MOCK_CURL = r'''import json
import os
import sys

url = sys.argv[-1]
is_cli = "/steipete/CodexBar/" in url
package = "cli" if is_cli else "plasma"
mode = os.environ.get("CURL_MODE", "ok")

if mode == "network" or mode == f"{package}-network":
    print("curl: Netzwerk nicht erreichbar", file=sys.stderr)
    print("\n000", end="")
    raise SystemExit(7)
if mode == "rate" or mode == f"{package}-rate":
    print(json.dumps({"message": "API rate limit exceeded"}) + "\n403", end="")
    raise SystemExit(22)

if is_cli:
    version = os.environ.get("CLI_REMOTE", "0.56.8")
    asset = f"CodexBarCLI-v{version}-linux-x86_64.tar.gz"
    assets = [{"name": asset, "browser_download_url": "https://example.invalid/" + asset}]
    if mode == "asset":
        assets = []
else:
    version = os.environ.get("PLASMA_REMOTE", "0.2.34")
    assets = []

release = {
    "tag_name": "v" + version,
    "draft": mode == "draft",
    "prerelease": mode == "prerelease",
    "assets": assets,
}
if mode == "tag":
    release["tag_name"] = version
print(json.dumps(release) + "\n200", end="")
'''


MOCK_NIX = r'''import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
url = args[-1]
kind = "cli" if "/releases/download/" in url else "plasma"
with Path(os.environ["NIX_LOG"]).open("a", encoding="utf-8") as handle:
    handle.write(json.dumps({"kind": kind, "args": args}) + "\n")
if os.environ.get("NIX_FAIL") == kind:
    print("simulierter Prefetch-Fehler", file=sys.stderr)
    raise SystemExit(1)
hash_value = os.environ["CLI_HASH"] if kind == "cli" else os.environ["PLASMA_HASH"]
print(json.dumps({"hash": hash_value}))
'''


def fail(message):
    raise AssertionError(message)


def write_executable(path, content):
    path.write_text(f"#!{sys.executable}\n{content}", encoding="utf-8")
    path.chmod(0o755)


def run_case(updater_command, sources=None, args=("--check",), extra_env=None):
    with tempfile.TemporaryDirectory(prefix="codexbar-update-test-") as case_name:
        case_dir = Path(case_name)
        sources_path = case_dir / "sources.json"
        sources_path.write_text(json.dumps(sources or BASE_SOURCES, indent=2) + "\n", encoding="utf-8")
        curl_path = case_dir / "curl"
        nix_path = case_dir / "nix"
        nix_log = case_dir / "nix.log"
        write_executable(curl_path, MOCK_CURL)
        write_executable(nix_path, MOCK_NIX)
        env = os.environ.copy()
        env.update({
            "CODEXBAR_SOURCES_FILE": str(sources_path),
            "CODEXBAR_CURL": str(curl_path),
            "CODEXBAR_NIX": str(nix_path),
            "NIX_LOG": str(nix_log),
            "CLI_HASH": CLI_HASH,
            "PLASMA_HASH": PLASMA_HASH,
        })
        if extra_env:
            env.update(extra_env)
        before = sources_path.read_bytes()
        before_entries = sorted(path.name for path in case_dir.iterdir())
        result = subprocess.run(
            [*updater_command, *args],
            cwd=case_dir,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        return {
            "before": before,
            "after": sources_path.read_bytes(),
            "before_entries": before_entries,
            "after_entries": sorted(path.name for path in case_dir.iterdir()),
            "sources": json.loads(sources_path.read_text(encoding="utf-8")),
            "nix_log_exists": nix_log.exists(),
            "nix_log": nix_log.read_text(encoding="utf-8") if nix_log.exists() else "",
            "result": result,
        }


def assert_error(result, label):
    if result.returncode in (0, 10):
        fail(f"{label}: Fehlercode erwartet, erhalten: {result.returncode}")
    if result.stdout:
        fail(f"{label}: stdout muss im Fehlerfall leer bleiben: {result.stdout!r}")
    if not result.stderr:
        fail(f"{label}: Fehlermeldung auf stderr fehlt")


def assert_unchanged(case, label, no_prefetch=False):
    if case["after"] != case["before"]:
        fail(f"{label}: sources.json wurde verändert")
    if any(name.startswith("sources.json.tmp.") for name in case["after_entries"]):
        fail(f"{label}: temporäre Quelldatei wurde nicht entfernt")
    if no_prefetch and case["nix_log_exists"]:
        fail(f"{label}: Hash-Ermittlung wurde trotz Fehler vor dem Update gestartet")


def test_check_current(updater):
    case = run_case(
        updater,
        extra_env={"CLI_REMOTE": "0.56.3", "PLASMA_REMOTE": "0.2.24"},
    )
    result = case["result"]
    if result.returncode != 0:
        fail(f"aktueller Check: Exit 0 erwartet: {result.stderr}")
    parsed = json.loads(result.stdout)
    if parsed != {
        "codexbar-cli": {"local": "0.56.3", "remote": "0.56.3", "outdated": False},
        "codexbar-plasma": {"local": "0.2.24", "remote": "0.2.24", "outdated": False},
    }:
        fail(f"aktueller Check: falsches JSON: {parsed}")
    assert_unchanged(case, "aktueller Check", no_prefetch=True)
    if case["after_entries"] != case["before_entries"]:
        fail("aktueller Check hat Dateien angelegt")


def test_check_outdated(updater):
    case = run_case(updater)
    result = case["result"]
    if result.returncode != 10:
        fail(f"veralteter Check: Exit 10 erwartet: {result.returncode}, {result.stderr}")
    parsed = json.loads(result.stdout)
    if parsed != {
        "codexbar-cli": {"local": "0.56.3", "remote": "0.56.8", "outdated": True},
        "codexbar-plasma": {"local": "0.2.24", "remote": "0.2.34", "outdated": True},
    }:
        fail(f"veralteter Check: falsches JSON: {parsed}")
    assert_unchanged(case, "veralteter Check", no_prefetch=True)


def test_invalid_local_schema(updater):
    invalid = copy.deepcopy(BASE_SOURCES)
    invalid["codexbar-cli"]["version"] = "v0.56.3"
    case = run_case(updater, sources=invalid)
    result = case["result"]
    assert_error(result, "ungültiges Quellschema")
    assert_unchanged(case, "Schemafehler", no_prefetch=True)


def test_release_errors(updater):
    for mode in ("draft", "prerelease", "tag", "asset", "rate", "network", "plasma-network"):
        case = run_case(updater, extra_env={"CURL_MODE": mode})
        result = case["result"]
        assert_error(result, mode)
        assert_unchanged(case, mode, no_prefetch=True)


def test_remote_older_is_error(updater):
    cases = (
        ("ältere CLI-Version", {"CLI_REMOTE": "0.56.2"}),
        ("ältere Plasma-Version", {"PLASMA_REMOTE": "0.2.23"}),
    )
    for args in (("--check",), ()):
        for label, env in cases:
            case = run_case(updater, args=args, extra_env=env)
            assert_error(case["result"], f"{label} ({'Check' if args else 'Update'})")
            assert_unchanged(case, f"{label} ({'Check' if args else 'Update'})", no_prefetch=True)


def test_update_and_hash_modes(updater):
    case = run_case(updater, args=())
    result = case["result"]
    if result.returncode != 0:
        fail(f"Update fehlgeschlagen: {result.stderr}")
    updated = case["sources"]
    cli = updated["codexbar-cli"]
    plasma = updated["codexbar-plasma"]
    if (cli["version"], cli["asset"], cli["hash"]) != (
        "0.56.8",
        "CodexBarCLI-v0.56.8-linux-x86_64.tar.gz",
        CLI_HASH,
    ):
        fail(f"CLI wurde falsch aktualisiert: {cli}")
    if (plasma["version"], plasma["hash"]) != ("0.2.34", PLASMA_HASH):
        fail(f"Plasma wurde falsch aktualisiert: {plasma}")
    calls = [json.loads(line) for line in case["nix_log"].splitlines()]
    if len(calls) != 2 or [call["kind"] for call in calls] != ["cli", "plasma"]:
        fail(f"Unerwartete Prefetch-Aufrufe: {calls}")
    if "--unpack" in calls[0]["args"]:
        fail("CLI-Archiv wurde fälschlich mit --unpack gehasht")
    if "--unpack" not in calls[1]["args"]:
        fail("Widget-Quellbaum wurde nicht mit --unpack gehasht")
    if any(name.startswith("sources.json.tmp.") for name in case["after_entries"]):
        fail("erfolgreiches Update hat eine temporäre Quelldatei hinterlassen")


def test_atomic_failures(updater):
    for env in (
        {"NIX_FAIL": "cli"},
        {"NIX_FAIL": "plasma"},
        {"CURL_MODE": "cli-network"},
        {"CURL_MODE": "plasma-network"},
    ):
        case = run_case(updater, args=(), extra_env=env)
        result = case["result"]
        assert_error(result, str(env))
        assert_unchanged(case, f"Fehler beim Update ({env})")


def test_current_update_does_not_prefetch(updater):
    case = run_case(
        updater,
        args=(),
        extra_env={"CLI_REMOTE": "0.56.3", "PLASMA_REMOTE": "0.2.24"},
    )
    result = case["result"]
    if result.returncode != 0 or result.stdout:
        fail(f"Update ohne Änderung verhält sich falsch: {result.returncode}, {result.stdout!r}")
    if case["after"] != case["before"] or case["nix_log_exists"]:
        fail("Update ohne Änderung hat geschrieben oder Hashes ermittelt")
    if case["after_entries"] != case["before_entries"]:
        fail("Update ohne Änderung hat Dateien angelegt")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Aufruf: test-update.py SCRIPT_FILE")
    updater = Path(sys.argv[1]).resolve()
    if not updater.is_file():
        raise SystemExit(f"Update-Programm nicht gefunden: {updater}")
    if os.access(updater, os.X_OK):
        updater_command = (str(updater),)
    else:
        updater_command = ("bash", "-euo", "pipefail", str(updater))
    tests = (
        test_check_current,
        test_check_outdated,
        test_invalid_local_schema,
        test_release_errors,
        test_remote_older_is_error,
        test_update_and_hash_modes,
        test_atomic_failures,
        test_current_update_does_not_prefetch,
    )
    for test in tests:
        test(updater_command)
    print(f"{len(tests)} Update-Vertragstests erfolgreich")


if __name__ == "__main__":
    main()
