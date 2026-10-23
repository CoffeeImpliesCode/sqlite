# Flake entry point for SQLite's Nix packages.
# Both linkage variants use package.nix; devShells provide build tools.
#
# SPDX-License-Identifier: LicenseRef-PublicDomain
# See FORK-LICENSE.md for what that identifier covers.

{
  description = "SQLite 3.53.4, the SQL database engine, packaged for Zig 0.17";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";
  };

  outputs = { self, nixpkgs }:
    let
      # These are native systems supported by package.nix; WASI needs a wasi-libc stdenv.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
        "x86_64-freebsd"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs:
        let
          mk = linkage: pkgs.callPackage ./package.nix {
            inherit linkage;
            zig = pkgs.zig_0_17;
          };
        in
        {
          # Upstream supports both archive and versioned shared-object delivery.
          static = mk "static";

          shared = mk "dynamic";

          default = mk "static";
        });

      # Tool shell only; package builds remain separate.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.zig_0_17
            # For the installed sqlite3.pc; no make is required.
            pkgs.pkg-config
          ];
        };
      });
    };
}