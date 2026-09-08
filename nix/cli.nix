{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  curl,
  sqlite,
}:

let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  source = sources."codexbar-cli";
in
stdenv.mkDerivation {
  pname = "codexbar-cli";
  version = source.version;

  src = fetchurl {
    url = "https://github.com/${source.owner}/${source.repo}/releases/download/v${source.version}/${source.asset}";
    hash = source.hash;
  };

  sourceRoot = ".";

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    curl
    sqlite
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 CodexBarCLI "$out/libexec/codexbar/CodexBarCLI"
    cp -r CodexBar_CodexBarCore.bundle "$out/libexec/codexbar/"
    mkdir -p "$out/bin"
    ln -s ../libexec/codexbar/CodexBarCLI "$out/bin/codexbar"

    runHook postInstall
  '';

  meta = {
    description = "Command-line interface for CodexBar";
    homepage = "https://github.com/steipete/CodexBar";
    license = lib.licenses.mit;
    mainProgram = "codexbar";
    platforms = [ "x86_64-linux" ];
  };
}
