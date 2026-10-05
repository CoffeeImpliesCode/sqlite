# Canonical development environment for the SQLite SDK.
#
# This is the environment a contributor should be in. It installs tools and
# nothing else: `packages` deliberately does not contain the SDK's own package,
# because entering a shell must not require building a library to have it.
#
# The package itself is defined once, in ./package.nix, and shared with
# flake.nix, so the two entry points cannot describe different builds. `outputs`
# below name that same derivation lazily -- they are attributes, not builds, so
# nothing is realised until `devenv build outputs.static` or
# `devenv build outputs.shared` is actually run.
#
# devenv.lock is not written here: the driver owns locks.

# Two facts about the environment a task actually runs in are handled once, in
# the `let` below, and every task uses them: devenv materialises a task as a
# generated shell program that inherits the caller's working directory, and
# `zig build` defaults both its local cache and its install prefix to
# directories inside the working tree. Neither is visible from a task body, and
# both decide whether a task can find this checkout or must write into it.
#
# SPDX-License-Identifier: LicenseRef-PublicDomain
# See FORK-LICENSE.md for what that identifier covers.

{ pkgs, ... }:

let
  # Kept as a value rather than inlined, so the version assertion below and the
  # package list cannot disagree about which compiler is meant.
  zig = pkgs.zig_0_16;

  sqlite = linkage: pkgs.callPackage ./package.nix {
    inherit linkage;
    zig = zig;
  };

  # The directory this module was evaluated against. `./.` is a path literal
  # resolved relative to the file that names it, so it is this checkout and
  # never the directory `devenv` was started from. `builtins.toString`
  # converts that path instead of interpolating it into a string, so what the
  # tasks below receive is this working tree: a plain `${./.}` would carry the
  # path's store context and copy this whole SDK into the read-only store, and
  # that copy is not the tree `build.zig` and `UPSTREAM.sha256` describe. No
  # host path is written in this file -- the value is read out of the module's
  # own location, so it tracks wherever this checkout is.
  sdk_root = builtins.toString ./.;

  # Where a task's build output goes. `zig build` keeps its local cache in
  # `.zig-cache/` and installs into `zig-out/`, both relative to the working
  # directory, and this checkout is a working tree on a volume mount that has to
  # stay byte-identical. A directory the caller exported always wins and is
  # never overwritten; otherwise it comes from `XDG_CACHE_HOME`, then `TMPDIR`,
  # and this file names no location of its own.
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

  # The same rule with the one extra requirement a task has: it must be able to
  # name that directory. An environment with nowhere outside the checkout to
  # write stops here, with the reason, instead of filling the tree.
  require_external_output = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      echo "sqlite3 devenv: ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME and TMPDIR are all unset," >&2
      echo "so there is nowhere outside this checkout to put build output." >&2
      echo "Export one of them at approved scratch, then run the task again." >&2
      exit 1
    fi
  '';

  # What every task below starts with. devenv materialises a task as a
  # generated shell program that inherits the caller's working directory, so
  # `devenv --from path:<sdk>` entered from a scratch project directory would
  # otherwise run each of these bodies where there is no `build.zig` and no
  # `UPSTREAM.sha256`. A per-task `cwd` would not reach that generated
  # program, and `$DEVENV_ROOT` is the scratch project itself -- exactly what
  # these bodies must not build in.
  in_sdk = ''
    ${zig_caches}
    ${require_external_output}
    cd "${sdk_root}" || exit 1
  '';

  # The flags every native build here shares: this workspace's eight jobs,
  # fixed, then the printed step list and a local cache outside the checkout.
  # `"''$@"` stays after them, so whatever a caller appended is still passed
  # on and still comes later; `devenv tasks run` forwards no argument of its
  # own, so it is the empty list on that route.
  native_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/native" "''$@"
  '';

  # The consumer package is a second build graph with its own manifest, so it
  # gets its own cache directory rather than sharing one with the library.
  consumer_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/consumer" "''$@"
  '';
in
{
  # No `gnumake` here, and that is a statement about this SDK rather than a
  # saving. Upstream's own build is autosetup plus make; this package uses
  # neither, and installing make would suggest otherwise. `pkg-config` is
  # installed because the build generates and installs a real sqlite3.pc.
  packages = [
    zig
    pkgs.pkg-config
    # For the provenance gate: `tools/check-provenance.sh` hashes with
    # sha256sum and openssl, and `tools/check-oracle.sh` diffs.
    pkgs.coreutils
    pkgs.openssl
    pkgs.diffutils
  ];

  assertions = [
    {
      assertion = zig.version == "0.16.0";
      message = "The SQLite SDK requires Zig 0.16.0; nixpkgs resolved zig_0_16 to ${zig.version}";
    }
  ];

  # The shell hook exports the same two directories the tasks use, by the same
  # rule, so an ordinary `devenv shell` session also leaves this checkout alone.
  # A value the caller exported is kept exactly as it is, and with nothing to
  # choose from the hook chooses nothing: only a task, which has to name the
  # directory, refuses to run.
  enterShell = ''
    ${zig_caches}
  '';

  # Lazy on purpose: naming a derivation realises nothing, and entering the
  # shell does not build either variant. `devenv build outputs.<name>` is the
  # real packaging route; the task names below print the equivalent flake
  # command, which needs the driver-owned lock.
  outputs.static = sqlite "static";
  outputs.shared = sqlite "dynamic";
  outputs.default = sqlite "static";

  # Every task name here is `namespace:name` and nothing else. devenv 2.4.1
  # accepts alphanumerics, `:`, `-` and `_` in a task name and rejects anything
  # else before any shell runs, so a name written with a `.` would never load.
  # Every name below uses `:`.
  tasks = {
    # Delivery output goes outside the checkout. The default step installs, and
    # `zig-out/` is a directory in the working tree, so the install prefix is
    # named here; the pkg-config file and the rpath the build normalises are
    # prefix-relative, so the installed tree is the same shape wherever it lands.
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

    # These run or compile; none of them installs, so each needs only the
    # external cache directory.
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

    # The upstream-interop gate: upstream's own sqlite3 shell, built from
    # src/shell.c, answers the same SQL the Zig tests answer, and its output is
    # compared byte for byte with the hand-computed table. It installs first
    # because that is where the shell lands, and the step's own reason for
    # existing is documented at build.zig's addOracle.
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

    # All six rows, running nothing. SQLite has no refusal list: every target
    # in build.zig's check_targets is walked, and the three link libraries each
    # one implies come from upstream's own detection rather than from a list
    # maintained here.
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

    # The dependent package in `consumer/`, built and run as itself. It reaches
    # the library through the relative path dependency in its own manifest, so
    # this is the proof that `dep.module("sqlite3")` works from outside this
    # package. Its own program checks a grouped aggregation against a table
    # hand-computed in the source.
    "sdk:consumer" = {
      description = "Build and run the separate consumer package against this SDK";
      exec = ''
        ${in_sdk}
        cd consumer
        zig build run ${consumer_flags}
      '';
    };

    # The checker runs against this checkout's own bytes and file set, which is
    # what `UPSTREAM.sha256` describes, so it is entered here rather than in the
    # directory the task happened to start in.
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

    # These two are the only bodies that do not enter this checkout, and that is
    # deliberate. They run a nested `devenv build`, which reads the project the
    # caller entered -- under `--from path:<sdk>` that is the scratch project
    # holding `.devenv/` and `devenv.lock` -- and its delivery output is a store
    # path, never a directory in this tree. Changing directory here would point
    # the nested command at a directory with no devenv state at all.
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