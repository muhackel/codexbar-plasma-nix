{
  description = "CodexBar CLI und Plasma-6-Widget mit eigener Update-Pflege";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
      packagesFor = system:
        let pkgs = pkgsFor system;
        in rec {
          codexbar-cli = pkgs.callPackage ./nix/cli.nix { };
          codexbar-plasma = pkgs.callPackage ./nix/plasma.nix { inherit codexbar-cli; };
          default = codexbar-plasma;
        };
      updateFor = system:
        let pkgs = pkgsFor system;
        in pkgs.writeShellApplication {
          name = "codexbar-update";
          runtimeInputs = with pkgs; [ curl jq nix coreutils gnused git ];
          text = builtins.readFile ./scripts/update.sh;
        };
    in {
      packages = forAllSystems packagesFor;

      overlays.default = final: prev:
        let
          additions = {
            codexbar-cli = final.callPackage ./nix/cli.nix { };
            codexbar-plasma = final.callPackage ./nix/plasma.nix { };
          };
        in
        assert builtins.intersectAttrs additions prev == { };
        additions;

      apps = forAllSystems (system: {
        update = {
          type = "app";
          program = nixpkgs.lib.getExe (updateFor system);
          meta.description = "Upstream-Pins prüfen oder atomar aktualisieren";
        };
      });

      devShells = forAllSystems (system:
        let pkgs = pkgsFor system;
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nix git curl jq shellcheck python3
              kdePackages.kpackage kdePackages.qttools
            ];
          };
        });

      checks = forAllSystems (system: import ./nix/checks.nix {
        pkgs = pkgsFor system;
        packages = packagesFor system;
        overlay = self.overlays.default;
        update = updateFor system;
        root = ./.;
      });
    };
}
