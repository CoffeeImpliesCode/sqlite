# Source-only package derivation for the SQLite SDK.
#
# One file, consumed by both flake.nix and devenv.nix, so the two entry points
# cannot describe different packages. It builds nothing but this repository: the
# native source is upstream's `src/` — the complete SQLite 3.53.4 amalgamation
# and the command-line shell that goes with it — imported whole from the
# `sqlite-amalgamation-3530400.zip` release artefact, and build.zig owns every
# compile flag and the whole installed layout. Nothing here restates a C flag,
# fetches an archive, reaches into a sibling checkout, or installs an artifact
# of its own. The one edit it makes is the rpath of the ELF files the build
# installed: Zig records its own build cache there, and that directory does not
# exist once a binary is installed.
#
# No lock file is written here. `flake.lock` and `devenv.lock` belong to the
# driver.
#
# SPDX-License-Identifier: LicenseRef-PublicDomain
# See FORK-LICENSE.md for what that identifier covers, and NOTICE.md for the
# public-domain dedication that covers everything in src/ and test/.

{ lib
, stdenv
, zig
, patchelf
  # Zig's own `std.builtin.LinkMode` spelling, passed straight through as
  # `-Dlinkage`. "static" and "dynamic" are two variants of one derivation, and
  # `""` passes nothing at all so the SDK's own default policy runs unchanged.
  # Unlike Lua, upstream's own build installs both a static archive and a
  # versioned shared object (`upstream/main.mk:1554-1563`), so neither is a
  # second-class delivery here; static is still the default because it is what a
  # C consumer's `-lsqlite3` resolves to without an rpath.
, linkage ? "static"
, optimize ? "ReleaseSafe"
}:

let
  requestedLinkage =
    if builtins.elem linkage [ "" "static" "dynamic" ] then linkage
    else throw "package.nix: linkage must be \"\", \"static\" or \"dynamic\", not ${toString linkage}";

# Everything except build outputs, version control and developer-tool state.
# Filtering by directory name rather than by an allow list means a file added
# here later is packaged without editing this file, while `.zig-cache/`,
# `zig-out/`, `.devenv/`, `.direnv/` and `result` stay out of a published output
# at any depth, including under consumer/. The upstream release metadata and
# the 1285-file upstream test suite are deliberately kept: they are upstream
# material with digests in UPSTREAM.sha256, and the audit surface is the whole
# upstream tree. That suite is 88 MiB of the source and is compiled by nothing
# here; it travels because `build.zig` has no upstream-test step rather than
# because this build needs it.
src = lib.cleanSourceWith {
  src = ./.;
  filter = path: _type:
    let name = builtins.baseNameOf (toString path); in
    !(lib.elem name [
      ".git"
      ".direnv"
      ".devenv"
      ".zig-cache"
      "zig-cache"
      "zig-pkg"
      "zig-out"
      "result"
    ]);
};

# patchelf rewrites ELF rpaths and does not read Mach-O, so the rpath
# normalisation in the install phase exists for ELF targets only, and the tool is
# a build input exactly where that code runs.
isElfTarget = !stdenv.hostPlatform.isDarwin;
in

# These packages build for the compiler's own native target. A cross build here
# would mean hand-building a libc-suffixed triple that has to track nixpkgs, so
# this derivation refuses one instead of silently producing a host-architecture
# library under a foreign name. The comparison is against stdenv's own
# platforms, which are pure values; `builtins.currentSystem` is not evaluable
# in a sandbox and is not used. A remote builder is unaffected: this compares
# build against host, not against any particular machine.
assert stdenv.buildPlatform.system == stdenv.hostPlatform.system;

stdenv.mkDerivation {
  pname = "sqlite3";
  version = "3.53.4";

  inherit src;

  strictDeps = true;
  dontPatch = true;

  # The real work is one `zig build install` in installPhase below. Disabling
  # configure and build phases keeps the Zig setup hook from running a first,
  # differently-flagged build of its own; `dontInstall` is deliberately NOT set,
  # because that is what would disable the real install phase.
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ zig ] ++ lib.optional isElfTarget patchelf;

  # SQLite links the C library, the C math library — `ceil` and `floor` are
  # called unconditionally at `src/sqlite3.c:136436-136437` — and, on the Unix
  # targets upstream's own detection selects, `dlopen` (`src/sqlite3.c:47240`)
  # and pthread (`src/sqlite3.c:30623-30625`). On nixpkgs those last three are
  # all inside one glibc, so `stdenv.cc.libc` is the whole of the native
  # dependency closure and nothing else is propagated. On Windows and on WASI
  # build.zig names none of them, from upstream's own arms rather than from a
  # judgement made here.
  propagatedBuildInputs = [ stdenv.cc.libc ];

  # The driver owns every gate for this SDK, and a Nix build is not a
  # verification receipt. No check phase is declared here rather than a check
  # phase that runs something smaller than the real gates; the commands that do
  # verify this package are in README.md and CHANGELOG.md.
  doCheck = false;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Both caches go under the Nix-provided TMPDIR, outside the unpacked source
    # tree, so a build cannot write into $src and so two parallel derivations
    # cannot share state. Any caller-supplied cache variables are left alone:
    # they are the caller's scratch, not this file's to clear.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"

    # build.zig owns the source list, the C flags, the absence of every
    # SQLITE_* compile option, the generated pkg-config file, the installed
    # headers and every installed path. Declaring any of them here as well would
    # create a second place where they can disagree with the build graph.
    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      ${lib.optionalString (requestedLinkage != "") "-Dlinkage=${requestedLinkage}"}

    # Zig records the build cache in the rpath of anything that links a dynamic
    # artifact it has just built (lib/std/Build/Step/Compile.zig:1192-1199), so
    # an installed binary names a directory that is gone, and Nix rejects an
    # installed file that names its build directory at all. Both Zig caches above
    # are under $TMPDIR, so dropping those entries and no other removes it: the
    # $ORIGIN/../lib build.zig adds, and every store path a real dependency
    # needs, stay. Symlinks are resolved first so a soname link is rewritten
    # through to the object and never replaced by a copy of it. The glob is wide
    # because build.zig delivers `libsqlite3.so.0.53.4` plus the `libsqlite3.so`
    # and `libsqlite3.so.0` links, and only the object itself needs rewriting.
    ${lib.optionalString isElfTarget ''
      for elf in "$out"/bin/* "$out"/lib/*.so*; do
        [ -f "$elf" ] || continue
        elf=$(readlink -f "$elf")
        rpath=$(patchelf --print-rpath "$elf") || rpath=""
        kept=""
        rest=$rpath
        while [ -n "$rest" ]; do
          entry="''${rest%%:*}"
          case "$entry" in
            "$TMPDIR"/*) ;;
            *) if [ -z "$kept" ]; then kept=$entry; else kept=$kept:$entry; fi ;;
          esac
          if [ "$entry" = "$rest" ]; then rest=""; else rest="''${rest#*:}"; fi
        done
        [ "$kept" = "$rpath" ] || patchelf --set-rpath "$kept" "$elf"
      done
    ''}

    runHook postInstall
  '';

  # The layout this derivation produces is the build graph's, not this file's:
  # $out/lib/libsqlite3.a (or libsqlite3.so.0.53.4 with the libsqlite3.so and
  # libsqlite3.so.0 links), $out/include/sqlite3.h and sqlite3ext.h — the two
  # files `upstream/main.mk:1613-1614` installs — $out/lib/pkgconfig/sqlite3.pc,
  # $out/bin/sqlite3 (upstream's own command-line shell, from src/shell.c), and
  # $out/share/licenses/sqlite/ with upstream's own dedication and this fork's
  # records. Both variants keep it; only the artifact kind differs. Nothing is
  # copied or generated by hand here, so `zig build install --prefix $out` and
  # `nix build` produce one layout by construction rather than two that have to
  # be kept in agreement.

  enableParallelBuilding = true;

  meta = {
    description = "SQLite 3.53.4, the SQL database engine, built from the official release amalgamation";
    longDescription = ''
      The SQLite 3.53.4 amalgamation and its command-line shell, compiled from
      the release archive's own src/ directory with Zig, with no configure
      script, no make, no autosetup and no build-time download. Ships the
      library, the sqlite3 program, the two public headers and a pkg-config
      file. No SQLITE_* compile option is defined, so this is SQLite's own
      default configuration; PRAGMA compile_options reports it at run time.
    '';
    license = lib.licenses.publicDomain;
    platforms = lib.platforms.unix;
    mainProgram = "sqlite3";
  };
}