# Koordinatornachweise zur Erstabnahme

Stand 2026-09-08. Die Abnahmekriterien `ac-06` und `ac-07` verlangen einen echten Lauf
gegen die GitHub-API und einen Paketbau. Beides ist in der Umsetzungsumgebung der
Mission nicht möglich — die Agenten arbeiten dort ohne Nix-Daemon und ohne Zugang zur
GitHub-API. Die Spec weist diese beiden Nachweise deshalb ausdrücklich dem Koordinator
zu. Hier stehen sie mit Kommando, Ausgabe und Exit-Code.

Alle Läufe fanden in vollständigen Kopien des Lieferstands außerhalb dieses
Arbeitsbaums statt; der Lieferstand selbst blieb unverändert bei den Pins `0.56.3`
und `0.2.24`.

## ac-06 — Prüfmodus ist schreibfrei und meldet korrekt

```
$ nix run --no-write-lock-file 'path:.#update' -- --check
{
  "codexbar-cli":    { "local": "0.56.3", "remote": "0.56.8", "outdated": true },
  "codexbar-plasma": { "local": "0.2.24", "remote": "0.2.34", "outdated": true }
}
Exit-Code 10
```

Die Ausgabe erfüllt das in der Spec festgelegte Schema; geprüft mit `jq -e` gegen die
Schlüsselmenge, das Versionsmuster `^[0-9]+\.[0-9]+\.[0-9]+$` beider Versionsfelder und
den Typ von `outdated`.

Schreibfreiheit: vor und nach dem Aufruf wurde über alle 16 Dateien außerhalb von `.git`
eine sortierte `sha256sum`-Liste erzeugt. Der `diff` beider Listen ist leer.

Fehlerpfad ohne Netz, ausgeführt in einem eigenen Netzwerk-Namespace:

```
$ unshare -r -n nix run --no-write-lock-file --offline 'path:.#update' -- --check
GitHub-Anfrage für steipete/CodexBar fehlgeschlagen (HTTP 000); Netzwerk oder Rate-Limit prüfen
Exit-Code 2
```

Der Exit-Code ist wie gefordert ungleich 0 und ungleich 10, die Meldung geht auf stderr.
Ein Netzfehler wird also nie als „aktuell“ gemeldet.

## ac-07 — Update-Lauf ermittelt Hashes selbst, Ergebnis baut

```
$ nix run --no-write-lock-file 'path:.#update'
Exit-Code 0
```

`diff -u` der zuvor gesicherten `nix/sources.json` gegen die fortgeschriebene Datei:

```
-    "version": "0.56.3",
-    "asset": "CodexBarCLI-v0.56.3-linux-x86_64.tar.gz",
-    "hash": "sha256-I06XMPYJy9igApa2WXc6UKPlEmrPo97Kkf5uPq2PfRw="
+    "version": "0.56.8",
+    "asset": "CodexBarCLI-v0.56.8-linux-x86_64.tar.gz",
+    "hash": "sha256-q5h4jhKEDlaJrlBb9icx4OoNscd+Y9ztoVibbnlaxbg="
-    "version": "0.2.24",
-    "hash": "sha256-2cTabBTzLiZF+6Ra3N92716VxKiKDEcATNqRmDY79Ao="
+    "version": "0.2.34",
+    "hash": "sha256-aS1sJGB65ETsJ91rFXsoXcGanBiPmHUWru5vJVJ3y1Y="
```

Der Sprung überspringt fünf CLI- und zehn Widget-Releases. Beide Pakete bauen mit den
selbst ermittelten Hashes ohne Mismatch:

```
$ nix build --no-write-lock-file 'path:.#codexbar-plasma' 'path:.#codexbar-cli'
/nix/store/2zdawpx0sdgjqx84sa1gikvg2pigci0y-codexbar-plasma-0.2.34
/nix/store/74q6xslsxffff1b5h2wvs4y0w750r53h-codexbar-cli-0.56.8
Exit-Code 0
```

## ac-10 — vollständiger Flake-Check am unveränderten Lieferstand

```
$ nix flake check --no-write-lock-file path:.
running 10 flake checks...
all checks passed!
Exit-Code 0
```

Gebaut wurden dabei `codexbar-cli`, `codexbar-plasma`, `overlay`, `plasma-structure`,
`cli-structure`, `sources-schema`, `pin-literals`, `workflow-yaml`, `shellcheck` und
`update-contract`.

Zur Aufrufform: `nix flake check` ohne `path:` löst das Flake über Git auf und bricht in
einem Baum ohne getrackte Dateien mit „Path 'flake.nix' … is not tracked by Git“ ab,
ohne eine einzige Prüfung zu starten. Belegt an einer Kopie ohne eine einzige getrackte
Datei: die Git-Form scheitert, die `path:`-Form läuft vollständig grün.

## Lieferstand unverändert

`nix/sources.json` trägt weiterhin `0.56.3` und `0.2.24`; SHA256 der Datei:
`ccccb9dbae7d2c5aebff7412586bf67c9adfdf1d1add703f60b6c12603526cf9`.
