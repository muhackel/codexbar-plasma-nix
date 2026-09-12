# codexbar-plasma-nix

Dieses Repository paketiert das Plasma-6-Widget `Lucenx9/codexbar-plasma` und
die Linux-CLI `steipete/CodexBar` als eigenständige Nix-Flake. Die beiden
Pakete werden unabhängig versioniert; die Pins liegen in
[`nix/sources.json`](nix/sources.json).

## Verwendung als Flake-Input

Im konsumierenden Flake wird dieses Repository als öffentlicher Input
eingetragen:

```nix
inputs.codexbar-plasma-nix.url = "github:muhackel/codexbar-plasma-nix";
```

Das Overlay wird bei der Paketkonfiguration aktiviert:

```nix
nixpkgs.overlays = [ inputs.codexbar-plasma-nix.overlays.default ];
```

Danach stehen `pkgs.codexbar-plasma` und `pkgs.codexbar-cli` zur Verfügung.
Die Umstellung eines Konsumenten ist eine eigene Folgemission; dieses
Repository enthält keine NixOS- oder Home-Manager-Konfiguration.
Nach der Umstellung bleibt im Konsumenten als Paketpflege nur der
Lock-Nachzug `nix flake update codexbar-plasma-nix`; die Versions- und
Hash-Chore liegt in diesem Repository.

## Lokale Ausgaben

Für `x86_64-linux` exportiert die Flake `packages.default`,
`packages.codexbar-plasma`, `packages.codexbar-cli`, `overlays.default`,
`devShells.default`, `apps.update` und Prüfungen unter `checks`.
`packages.default` ist das Widget.

```sh
nix build .#codexbar-plasma
nix build .#codexbar-cli
nix run .#update -- --check
```

Die vollständigen Abläufe stehen in [`build.md`](build.md).

Die Update-Automation prüft täglich um 04:17, 12:17 und 20:17 UTC auf neue
Upstream-Versionen. Update-PRs nennen für beide Pakete die bisherige und die
neue Version sowie das Ergebnis von `nix flake check`.

Für Prüfungen im unversionierten Umsetzungs-Snapshot ist die schreibfreie
`path:`-Form mit `--no-write-lock-file` zu verwenden, zum Beispiel:

```sh
nix flake check --no-write-lock-file path:.
nix run --no-write-lock-file 'path:.#update' -- --check
```

Der Lieferstand enthält bereits eine unveränderte `flake.lock`. Der
Koordinator führt die netzabhängigen Live-Nachweise in einer separaten Kopie
des Lieferstands aus und vergleicht dabei den Dateibaum beziehungsweise die
aktualisierte `nix/sources.json` mit dem Ausgangszustand.
