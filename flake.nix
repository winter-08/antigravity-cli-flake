{
  description = "Nix flake for Google Antigravity CLI (agy)";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      inherit (lib.attrsets) genAttrs optionalAttrs;
      inherit (lib.lists) elem;
      inherit (lib.meta) getExe;
      inherit (lib.strings) fileContents getName;

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forAllSystems = genAttrs supportedSystems;

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate =
            pkg:
            elem (getName pkg) [
              "antigravity-cli"
              "antigravity-cli-musl"
            ];
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          antigravity-cli = pkgs.callPackage ./package.nix { };
        in
        {
          inherit antigravity-cli;
          default = antigravity-cli;
        }
        // optionalAttrs pkgs.stdenvNoCC.hostPlatform.isLinux {
          antigravity-cli-musl = pkgs.callPackage ./package.nix {
            useMusl = true;
          };
        }
      );

      overlays.default = final: _prev: {
        antigravity-cli = final.callPackage ./package.nix { };
        antigravity-cli-musl = final.callPackage ./package.nix {
          useMusl = true;
        };
      };

      apps = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          agy = self.packages.${system}.antigravity-cli;
          update = pkgs.writeShellApplication {
            name = "update-antigravity-cli";
            runtimeInputs = [
              pkgs.curl
              pkgs.jq
              pkgs.nix
            ];
            text = fileContents ./scripts/update.sh;
          };
        in
        {
          default = {
            type = "app";
            program = getExe agy;
            meta.description = "Run Antigravity CLI (agy)";
          };

          agy = {
            type = "app";
            program = getExe agy;
            meta.description = "Run Antigravity CLI (agy)";
          };

          update = {
            type = "app";
            program = getExe update;
            meta.description = "Pin the newest Antigravity CLI release in sources.json";
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
