# Flake interface for the SQLite SDK.
#
# Portable counterpart to devenv.nix. Both call ./package.nix, so the package a
# flake builds and the package devenv builds are the same derivation; this file
# only decides which systems are exposed and which variants of that derivation
# they get.
#
# Canonical development is `devenv shell` (see devenv.nix and .envrc). This
# flake exists so the SDK can be built and consumed off this host. `nix develop`
# here is parity, not the canonical entry point, and it deliberately does not
# build the SDK: entering a shell must not require building a library.
#
# flake.lock is not written here: the driver owns locks.
#
# SPDX-License-Identifier: LicenseRef-PublicDomain
# See FORK-LICENSE.md for what that identifier covers.

{
  description = "SQLite 3.53.4, the SQL database engine, packaged for Zig 0.16";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";
  };

  outputs = { self, nixpkgs }:
    let
      # Unix systems only, which is the same boundary package.nix asserts: it
      # builds for the compiler's native target rather than hand-building a
      # cross triple. Documented in README.md, not worked around here.
      #
      # There is no wasm32-wasi entry here either, and that is a statement about
      # this file rather than about SQLite: upstream's own `__wasi__` arm
      # (`src/sqlite3.c:11676-11685`) compiles, and `zig build check` walks it in
      # the six-target baseline. A Nix package for it would need a wasi-libc
      # stdenv rather than this derivation's, and adding a second derivation
      # that is not exercised here would be an untested claim.
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
            zig = pkgs.zig_0_16;
          };
        in
        {
          # Upstream's own build installs both deliveries — an archive and a
          # versioned shared object — so neither is the odd one out here and
          # `default` names the one a C consumer's bare `-lsqlite3` resolves
          # to without an rpath.
          static = mk "static";

          # A separate variant of the same derivation, not a second SDK.
          # "shared" names the artefact; the flag it passes is Zig's own
          # `-Dlinkage=dynamic`.
          shared = mk "dynamic";

          default = mk "static";
        });

      # Parity only. The canonical development environment is devenv.nix.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.zig_0_16
            # `pkg-config` for the installed sqlite3.pc. Not gnumake: this SDK
            # builds without make, and shipping it would suggest otherwise.
            pkgs.pkg-config
          ];
        };
      });
    };
}