# Development environment for SQLite.
# Uses package.nix for outputs and provides tools for the repository tasks.

# Tasks run from this checkout and keep caches and install outputs outside it.
#
# SPDX-License-Identifier: LicenseRef-PublicDomain
# See FORK-LICENSE.md for what that identifier covers.

{ pkgs, ... }:

let
  zig = pkgs.zig_0_17;

  sqlite = linkage: pkgs.callPackage ./package.nix {
    inherit linkage;
    zig = zig;
  };

  # Resolve this checkout from the module file, not the caller's working directory.
  # Avoid interpolating a store path that would copy the source tree.
  sdk_root = builtins.toString ./.;

  # Keep caches outside the source tree; preserve exported cache paths.
  # Otherwise prefer XDG_CACHE_HOME, then TMPDIR.
  zig_caches = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="$XDG_CACHE_HOME/sqlite3/zig-local-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="$TMPDIR/sqlite3/zig-local-cache"
      fi
    fi
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="$XDG_CACHE_HOME/sqlite3/zig-global-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/sqlite3/zig-global-cache"
      fi
    fi
    if [ -n "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      mkdir -p "$ZIG_LOCAL_CACHE_DIR"
    fi
    if [ -n "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
    fi
  '';

  # Stop a task when no external local cache directory is available.
  require_external_output = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      echo "sqlite3 devenv: ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME and TMPDIR are all unset," >&2
      echo "so there is nowhere outside this checkout to put build output." >&2
      echo "Export one of them at approved scratch, then run the task again." >&2
      exit 1
    fi
  '';

  # Generated task shells inherit caller cwd, so enter this checkout explicitly.
  # This ensures build.zig and provenance files resolve from the package root.
  in_sdk = ''
    ${zig_caches}
    ${require_external_output}
    cd "${sdk_root}" || exit 1
  '';

  # Shared job count, summary and local cache; caller args follow these options.
  native_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/native" "''$@"
  '';

  # Give the standalone consumer build its own cache directory.
  consumer_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/consumer" "''$@"
  '';
in
{
  # `pkg-config` reads the installed sqlite3.pc; no make is required.
  packages = [
    zig
    pkgs.pkg-config
    pkgs.coreutils
    pkgs.openssl
    pkgs.diffutils
  ];

  assertions = [
    {
      assertion = zig.version == "0.17.0";
      message = "The SQLite SDK requires Zig 0.17.0; nixpkgs resolved zig_0_17 to ${zig.version}";
    }
  ];

  # Shell and tasks share cache setup; only tasks require a writable output path.
  enterShell = ''
    ${zig_caches}
  '';

  # Derivations are lazy; build them with `devenv build outputs.<name>`.
  outputs.static = sqlite "static";
  outputs.shared = sqlite "dynamic";
  outputs.default = sqlite "static";

  tasks = {
    # Keep installed outputs under the external cache, not in the checkout.
    "sdk:build" = {
      description = ''
        Compile the amalgamation and upstream's sqlite3 shell (default step) and
        install the delivery tree under the external cache rather than in this
        checkout.
      '';
      exec = ''
        ${in_sdk}
        zig build --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/static" ${native_flags}
      '';
    };

    "sdk:build:shared" = {
      description = ''
        Compile the library as a shared object carrying upstream's
        libsqlite3.so.0 ABI name, and install it under its own external prefix.
      '';
      exec = ''
        ${in_sdk}
        zig build -Dlinkage=dynamic --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/dynamic" ${native_flags}
      '';
    };

    # Test and smoke tasks use external caches without installing.
    "sdk:test" = {
      description = "Run the behavioural tests for the host target";
      exec = ''
        ${in_sdk}
        zig build test ${native_flags}
      '';
    };

    "sdk:test:release-safe" = {
      description = "Run the behavioural tests in ReleaseSafe";
      exec = ''
        ${in_sdk}
        zig build test -Doptimize=ReleaseSafe ${native_flags}
      '';
    };

    "sdk:smoke" = {
      description = "Run the deterministic example";
      exec = ''
        ${in_sdk}
        zig build smoke ${native_flags}
      '';
    };

    "sdk:oracle" = {
      description = ''
        Run upstream's own sqlite3 shell over tools/fixture/aggregate.sql and
        compare its output byte for byte with tools/fixture/expected.tsv. This is
        a front-end interoperability check, not a run of SQLite's TCL suite.
      '';
      exec = ''
        ${in_sdk}
        zig build oracle --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/oracle" ${native_flags}
      '';
    };

    "sdk:check" = {
      description = "Compile and link the library, facade, tests, example and shell for all six check targets, running nothing";
      exec = ''
        ${in_sdk}
        zig build check ${native_flags}
      '';
    };

    "sdk:check:shared" = {
      description = "The same six-target compile check against the shared object";
      exec = ''
        ${in_sdk}
        zig build check -Dlinkage=dynamic ${native_flags}
      '';
    };

    # Build the separate consumer package to exercise the dependency interface.
    "sdk:consumer" = {
      description = "Build and run the separate consumer package against this SDK";
      exec = ''
        ${in_sdk}
        cd consumer
        zig build run ${consumer_flags}
      '';
    };

    # Run the checker from the checkout whose manifest it verifies.
    "sdk:provenance" = {
      description = ''
        Check the 1299 recorded upstream digests, the exact native file set, the
        Fossil check-in identity against upstream's own manifest, the version in
        three places, the public-domain grant, the preserved upstream README and
        the fixture-versus-tests SQL agreement. This is a source-integrity
        check, not a build gate.
      '';
      exec = ''
        ${in_sdk}
        bash tools/check-provenance.sh
      '';
    };

    # Package tasks run in the caller's devenv project; do not change directory.
    # Their outputs are Nix store paths, not source-tree directories.
    "sdk:package:static" = {
      description = ''
        Build the static Nix variant through devenv's own lazy output. No lock
        is needed by this path; `devenv build outputs.static` resolves the
        pinned input from devenv.lock, which the driver owns.
      '';
      exec = "devenv build outputs.static";
    };

    "sdk:package:shared" = {
      description = "Build the shared Nix variant through devenv's own lazy output";
      exec = "devenv build outputs.shared";
    };
  };
}