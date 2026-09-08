# Arbeitsregeln

## Git

Direkte Commits auf `main` sind nicht zulässig. Jede Änderung erfolgt auf
einem Feature-Branch. Feature-Branches werden ausschließlich mit einem
`--no-ff`-Merge nach `main` übernommen. Commits erhalten einen deutschen
Betreff ohne Präfix und ohne KI-Banner.

## Pins und Update-App

Alle Upstream-Versionen und Hashes stehen ausschließlich in
`nix/sources.json`. `nix run .#update -- --check` prüft beide neuesten
Nicht-Draft- und Nicht-Prerelease-Releases, schreibt nichts und liefert das
festgelegte JSON. `nix run .#update` aktualisiert die Datei atomar; ein Fehler
bei einem Upstream lässt die vorhandene Datei unverändert.

Die CLI-Pin steht aktuell auf `0.57.0`, die Widget-Pin auf `0.2.35`. Bei der
Hash-Ermittlung gilt: Für das CLI-Release-Archiv wird der Hash der Archivdatei
ermittelt, weil der Ausdruck `fetchurl` verwendet. Für das Widget wird der
Hash des entpackten Quellbaums ermittelt, weil `fetchFromGitHub` verwendet
wird. Ein gemeinsames `--unpack` für beide Quellen wäre daher falsch.

## Laufzeit-Selbstupdater des Widgets

Das Paket installiert den Upstream-Selbstupdater
`scripts/update-widget.sh` bewusst unverändert.
Im Modus `--check` prüft er nur auf eine neue Version. Im Modus `--install`
lädt er ein neueres Plasmoid und installiert es mit `kpackagetool6` nach
`~/.local/share`. Dieses lokale Paket schattet anschließend das Store-Paket
ab. Der Konflikt zwischen Laufzeit-Selbstupdater und dem unveränderlichen
Store-Pin ist bekannt und wird bewusst nicht behoben, damit das Verhalten dem
Referenzausdruck entspricht.

## Wartung

Nach einem Versionssprung können sich die Bibliotheksabhängigkeiten der
vorgebauten CLI ändern. Scheitert `autoPatchelfHook`, müssen die fehlenden
Laufzeitbibliotheken im CLI-Ausdruck ergänzt und beide Pakete erneut geprüft
werden. Eine Änderung am Laufzeit-Selbstupdater gehört nicht zu dieser
Packaging-Chore.
