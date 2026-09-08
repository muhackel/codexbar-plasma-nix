"""Prüft Nix-Ausdrücke auf verteilte Versions- und Hash-Pins."""

import re
import sys
from pathlib import Path


def without_comments(text):
    # Strings bleiben erhalten, damit Pins darin ebenfalls auffallen.
    result = []
    mode = "code"
    i = 0
    while i < len(text):
        if mode == "code" and text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end == -1:
                raise ValueError("Nicht abgeschlossener Nix-Kommentar")
            result.extend("\n" if c == "\n" else " " for c in text[i:end + 2])
            i = end + 2
            continue
        if mode == "code" and text[i] == "#":
            end = text.find("\n", i)
            if end == -1:
                end = len(text)
            result.extend(" " * (end - i))
            i = end
            continue
        if mode == "code" and text.startswith("''", i):
            mode = "indented"
            result.extend("''")
            i += 2
            continue
        if mode == "indented" and text.startswith("''", i):
            # Nix-Escapes innerhalb eingerückter Strings.
            if i + 2 < len(text) and text[i + 2] in "'$\\":
                result.extend(text[i:i + 3])
                i += 3
                continue
            mode = "code"
            result.extend("''")
            i += 2
            continue
        if mode == "quoted" and text[i] == "\\":
            result.extend(text[i:i + 2])
            i += 2
            continue
        if text[i] == '"' and mode in ("code", "quoted"):
            mode = "quoted" if mode == "code" else "code"
        result.append(text[i])
        i += 1
    return "".join(result)


root = Path(sys.argv[1])
pattern = re.compile(r"sha256-|[0-9]+\.[0-9]+\.[0-9]+")
failed = False
for path in [root / "flake.nix", *sorted((root / "nix").glob("*.nix"))]:
    for number, line in enumerate(without_comments(path.read_text()).splitlines(), 1):
        if pattern.search(line):
            print(f"{path}:{number}: Pin außerhalb von sources.json", file=sys.stderr)
            failed = True
sys.exit(1 if failed else 0)
