# Bauen und Entwickeln

## Voraussetzungen

Benötigt werden Nix mit aktivierten Flakes und ausreichend Speicherplatz für
die Fixed-Output-Quellen und den Bau. Für den automatischen Update-Workflow
gelten diese Betriebsvoraussetzungen:

- Das Repository hat ein öffentliches GitHub-Remote.
- GitHub Actions sind für das Repository aktiviert.
- In den Repository-Einstellungen ist **Allow GitHub Actions to create and
  approve pull requests** aktiviert.

Fehlt die PR-Einstellung, scheitert der PR-Schritt trotz korrekter
Workflow-`permissions`. Das Aktivieren der Repository-Einstellung und der
Actions obliegt dem Koordinator, nicht dem Workflow.

`flake.lock` ist Bestandteil des Lieferstands und fixiert den Nixpkgs-Stand.
Der Generator übernimmt diese Datei unverändert. Dadurch legt der erste
Prüfaufruf keine Lock-Datei an.

## Entwicklungsumgebung

Die Werkzeuge des Projekts sind in `devShells.default` enthalten. Shell starten:

```sh
nix develop
```

## Bauen und Starten

Beide Pakete können unabhängig gebaut werden:

```sh
nix build .#codexbar-plasma
nix build .#codexbar-cli
```

Das Standardpaket ist das Widget:

```sh
nix build .
```

Die CLI kann nach ihrem eigenen Bau direkt gestartet werden:

```sh
nix build .#codexbar-cli
./result/bin/codexbar --help
```

Das Widget ist für Plasma 6 bestimmt und wird über die Plasma-
Appletverwaltung aktiviert.

Die Update-App läuft im Prüfmodus oder aktualisiert die Pins:

```sh
nix run .#update -- --check
nix run .#update
```

## Testen

Die vollständige lokale Prüfung umfasst Paketbau, Overlay-, Struktur-, Pin-,
YAML- und Shellcheck-Prüfungen sowie netzlose Vertragstests der Update-App:

```sh
nix flake check --no-write-lock-file path:.
nix flake show --json path:.
```

Im Umsetzungs-Snapshot sind die neu angelegten Dateien noch nicht in Git
sichtbar. Deshalb ist hier die `path:`-Form verbindlich; der gewöhnliche
Git-basierte Aufruf kann mit „Path … is not tracked by Git“ abbrechen. Der
Koordinator führt die vollständige Prüfung am unveränderten Lieferstand mit
Netzzugriff aus, falls ein Paketbau in dieser Umgebung nur an fehlendem Netz
scheitert.

Der Prüfmodus der Update-App schreibt nichts. Sein JSON kann mit `jq -e`
validiert werden; Exit-Code `0` bedeutet aktuelle Pins, `10` mindestens einen
veralteten Pin. Jeder andere Fehler, einschließlich Netzwerk- oder
GitHub-Rate-Limit-Fehler, liefert einen anderen Exit-Code und eine Meldung auf
`stderr`.
Ist eine ermittelte Remote-Version älter als der lokale Pin, behandelt die
App das als Fehler mit einem anderen Exit-Code und lässt die Quelldatei
unverändert; ein stiller Downgrade gilt nicht als „aktuell“.

## Projektspezifisches

### Updates vollständig durchführen

In einem versionierten Checkout:

1. `nix run .#update -- --check` ausführen und die JSON-Ausgabe prüfen.
2. Für einen Bump `nix run .#update` ausführen. Die App fragt pro Upstream die
   Releases ab, überspringt Drafts und Prereleases, prüft das Tag-Format und
   sucht das vorgeschriebene CLI-Asset.
3. Die Änderung an `nix/sources.json` prüfen.
4. `nix flake check --no-write-lock-file path:.` ausführen; dieser Check baut
   beide Pakete.
5. Den geprüften Pin-Bump auf einem Feature-Branch als Pull Request einreichen.

Im Konsumenten wird danach lediglich der Flake-Lock nachgezogen:

```sh
nix flake update codexbar-plasma-nix
```

Die GitHub Action führt diesen Ablauf täglich nach Zeitplan oder auf
`workflow_dispatch` aus. Bleibt `nix/sources.json` unverändert, erstellt sie
keinen Branch und keinen Pull Request. Bei einer Änderung läuft die Prüfung
vor der PR-Erstellung. Auch wenn sie fehlschlägt, wird ein Pull Request mit
Prüfergebnis und Fehlerauszug angelegt; der Job bleibt fehlgeschlagen, damit
kein ungeprüfter Bump unbemerkt nach `main` gelangt.

Der Koordinator belegt die netzabhängigen Live-Läufe in einer separaten
Arbeitskopie. Für `--check` wird der vollständige Dateibaum außerhalb von
`.git` vor und nach dem Aufruf als sortierte `sha256sum`-Liste verglichen.
Für den Schreibmodus wird der Lieferstand in ein temporäres Verzeichnis
kopiert, `nix/sources.json` vorher gesichert und anschließend
`nix run --no-write-lock-file 'path:.#update'` ausgeführt. Die Änderung wird
mit `diff -u` gegen diese Sicherung geprüft; danach laufen
`nix build --no-write-lock-file 'path:.#codexbar-plasma'` und
`nix build --no-write-lock-file 'path:.#codexbar-cli'`. Diese Nachweise gehören
nicht in den Snapshot-Lauf.

### Hash-Ermittlung

Für die CLI wird der SRI-Hash der Archivdatei ohne Entpacken ermittelt, zum
Beispiel:

```sh
nix store prefetch-file --json \
  https://github.com/steipete/CodexBar/releases/download/v0.56.3/CodexBarCLI-v0.56.3-linux-x86_64.tar.gz
```

Für das Widget wird der Hash des entpackten GitHub-Quellbaums ermittelt:

```sh
nix store prefetch-file --json --unpack \
  https://github.com/Lucenx9/codexbar-plasma/archive/refs/tags/v0.2.24.tar.gz
```

Die Update-App erledigt beide Varianten selbst und schreibt die Ergebnisse in
`nix/sources.json`. Die Semantik darf nicht vertauscht werden: `fetchurl`
erwartet das Archiv, `fetchFromGitHub` den entpackten Baum.

### Hash-Mismatch

Bei einem Hash-Mismatch zuerst Version, Tag-Präfix, Asset-Namen und die
Hash-Semantik prüfen. Das CLI-Archiv darf nicht mit `--unpack` prefetched
werden; beim Widget ist `--unpack` erforderlich. Wenn die Update-App bei
unveränderten Versionen keinen neuen Hash ermittelt, die Hashes manuell mit
den oben beschriebenen `nix store prefetch-file`-Aufrufen bestimmen, die
Pins in `nix/sources.json` prüfen und den Bau erneut ausführen. Bei einem
Fehler der Update-App bleibt die Quelldatei durch das temporäre Schreiben
und atomare `mv` unverändert; manuelle Änderungen schützt dieser Mechanismus
nicht.

### `autoPatchelfHook` nach einem Versionssprung

Bricht der CLI-Bau mit einer nicht erfüllten Abhängigkeit von
`autoPatchelfHook` ab, die Meldung auswerten und die fehlende Bibliothek in
`buildInputs` des CLI-Ausdrucks aufnehmen. Danach `nix build .#codexbar-cli`
und `nix flake check` erneut ausführen. Ein solcher Fehler ist ein erwarteter
Wartungsfall bei vorgebauten Upstream-Binaries.
