{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  bash,
  coreutils,
  curl,
  gnugrep,
  jq,
  kdePackages,
  libnotify,
  python3,
  codexbar-cli,
}:

let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  source = sources."codexbar-plasma";
in
stdenvNoCC.mkDerivation {
  pname = "codexbar-plasma";
  version = source.version;

  src = fetchFromGitHub {
    owner = source.owner;
    repo = source.repo;
    rev = "v${source.version}";
    hash = source.hash;
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    appletDir="$out/share/plasma/plasmoids/app.codexbar.plasma"
    install -d "$appletDir/docs" "$appletDir/scripts"
    cp -r contents "$appletDir/"
    install -Dm644 metadata.json LICENSE NOTICE.md README.md "$appletDir/"
    install -Dm644 \
      docs/codexbar-plasma-overview.png \
      docs/codexbar-plasma-codex.png \
      "$appletDir/docs/"
    install -Dm755 scripts/update-widget.sh "$appletDir/scripts/update-widget.sh"
    patchShebangs "$appletDir/scripts/update-widget.sh"

    runHook postInstall
  '';

  propagatedUserEnvPkgs = [
    bash
    codexbar-cli
    coreutils
    curl
    gnugrep
    jq
    kdePackages.kpackage
    kdePackages.plasma5support
    libnotify
    python3
  ];

  passthru = {
    codexbarCli = codexbar-cli;
  };

  meta = {
    description = "KDE Plasma 6 widget for CodexBar";
    homepage = "https://github.com/Lucenx9/codexbar-plasma";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
