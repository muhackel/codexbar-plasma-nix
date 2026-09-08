{ pkgs, packages, overlay, update, root }:
let
  inherit (packages) codexbar-cli codexbar-plasma;
  overlayResult = overlay overlaid pkgs;
  overlaid = pkgs.extend overlay;
  python = pkgs.python3.withPackages (p: [ p.pyyaml ]);
in {
  inherit codexbar-cli codexbar-plasma;

  overlay = assert builtins.attrNames overlayResult == [ "codexbar-cli" "codexbar-plasma" ];
    assert builtins.intersectAttrs overlayResult pkgs == { };
    assert overlaid.codexbar-cli.drvPath == codexbar-cli.drvPath;
    assert overlaid.codexbar-plasma.drvPath == codexbar-plasma.drvPath;
    pkgs.runCommand "codexbar-overlay-check" { } ''
      touch "$out"
    '';

  plasma-structure = assert codexbar-plasma.meta.platforms == [ "x86_64-linux" ];
    assert codexbar-plasma.codexbarCli.drvPath == codexbar-cli.drvPath;
    assert map (p: p.drvPath) codexbar-plasma.propagatedUserEnvPkgs == map (p: p.drvPath) (with pkgs; [
      bash codexbar-cli coreutils curl gnugrep jq kdePackages.kpackage
      kdePackages.plasma5support libnotify python3
    ]);
    pkgs.runCommand "codexbar-plasma-structure" { nativeBuildInputs = [ pkgs.diffutils ]; } ''
      applet=${codexbar-plasma}/share/plasma/plasmoids/app.codexbar.plasma
      test -d "$applet/contents"
      # contents wird vollständig vom Upstream übernommen; die übrigen Pfade sind fest.
      (cd "$applet"; find . -path ./contents -prune -o -type f -print | sed 's|^./||'; echo contents/) | LC_ALL=C sort > actual
      LC_ALL=C sort ${./plasma-files.txt} > expected
      diff -u expected actual
      diff -r ${codexbar-plasma.src}/contents "$applet/contents"
      test -x "$applet/scripts/update-widget.sh"
      head -n 1 "$applet/scripts/update-widget.sh" | grep -E '^#!${builtins.storeDir}/[^ ]+/bin/(env |)bash'
      touch "$out"
    '';

  cli-structure = pkgs.runCommand "codexbar-cli-structure" { } ''
    cli=${codexbar-cli}
    test -L "$cli/bin/codexbar"
    test "$(readlink -f "$cli/bin/codexbar")" = "$cli/libexec/codexbar/CodexBarCLI"
    test -x "$cli/libexec/codexbar/CodexBarCLI"
    test -d "$cli/libexec/codexbar/CodexBar_CodexBarCore.bundle"
    ${pkgs.glibc.bin}/bin/ldd "$cli/libexec/codexbar/CodexBarCLI" > ldd-output
    cat ldd-output
    if grep -q 'not found' ldd-output; then exit 1; fi
    touch "$out"
  '';

  sources-schema = pkgs.runCommand "codexbar-sources-schema" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq -e -f ${./sources.jq} ${./sources.json} > /dev/null
    touch "$out"
  '';

  pin-literals = pkgs.runCommand "codexbar-pin-literals" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python ${./check-pin-literals.py} ${root}
    touch "$out"
  '';

  workflow-yaml = pkgs.runCommand "codexbar-workflow-yaml" { nativeBuildInputs = [ python ]; } ''
    python - <<'PY'
    from pathlib import Path
    import yaml
    paths = list(Path("${root}/.github/workflows").glob("*.yml"))
    assert paths, "Workflow fehlt"
    for path in paths:
        with path.open() as stream:
            data = yaml.safe_load(stream)
        assert isinstance(data, dict) and isinstance(data.get("jobs"), dict), path
    PY
    touch "$out"
  '';

  # writeShellApplication führt shellcheck beim Bau aus.
  shellcheck = update;

  update-contract = pkgs.runCommand "codexbar-update-contract" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    python ${./test-update.py} ${pkgs.lib.getExe update}
    touch "$out"
  '';
}
