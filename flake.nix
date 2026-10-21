{
  description = "Nix packages and NixOS modules for Octelium";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = lib.intersectLists lib.systems.flakeExposed [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      overlays.default = final: _prev: import ./pkgs { pkgs = final; };

      nixosModules = {
        default = self.nixosModules.octelium;
        octelium = ./modules/nixos;
      };

      packages = forAllSystems (
        pkgs:
        let
          octeliumPkgs = lib.filterAttrs (_: lib.meta.availableOn pkgs.stdenv.hostPlatform) (
            import ./pkgs { inherit pkgs; }
          );
        in
        octeliumPkgs // { default = octeliumPkgs.octelium-tools; }
      );

      checks = forAllSystems (
        pkgs:
        let
          inherit (pkgs.stdenv.hostPlatform) system;
          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              (lib.fileset.fileFilter (file: file.hasExt "nix") ./.)
              ./.github
              ./scripts
              ./tests
            ];
          };
        in
        lib.removeAttrs self.packages.${system} [ "default" ]
        // {
          formatting = pkgs.runCommand "octelium-nix-formatting" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
            cd ${src}
            find . -name '*.nix' -exec nixfmt --check {} +
            touch $out
          '';

          lint =
            pkgs.runCommand "octelium-nix-lint"
              {
                nativeBuildInputs = [
                  pkgs.actionlint
                  pkgs.shellcheck
                ];
              }
              ''
                cd ${src}
                shellcheck scripts/*.sh tests/*.sh
                actionlint .github/workflows/*.yaml
                touch $out
              '';

          update-script =
            pkgs.runCommand "octelium-nix-update-script"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gawk
                  pkgs.gnugrep
                  pkgs.gnused
                  pkgs.jq
                  pkgs.openssl
                ];
              }
              ''
                cp -r ${src} source
                chmod -R u+w source
                patchShebangs source
                source/tests/test-update.sh
                touch $out
              '';
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          nixos = import ./tests/nixos.nix {
            inherit pkgs;
            module = self.nixosModules.octelium;
          };
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = [
            pkgs.actionlint
            pkgs.coreutils
            pkgs.gawk
            pkgs.gh
            pkgs.gnugrep
            pkgs.gnused
            pkgs.jq
            pkgs.nixfmt
            pkgs.shellcheck
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
