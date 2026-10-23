# Source-only Nix derivation shared by flake.nix and devenv.nix.
# build.zig defines compilation and installation; this derivation normalizes RPATHs.
#
# SPDX-License-Identifier: LicenseRef-PublicDomain
# See FORK-LICENSE.md for what that identifier covers, and NOTICE.md for the
# public-domain dedication that covers everything in src/ and test/.

{ lib
, stdenv
, zig
, patchelf
  # Linkage selects static or shared delivery; empty leaves build.zig's default.
, linkage ? "static"
, optimize ? "ReleaseSafe"
}:

let
  requestedLinkage =
    if builtins.elem linkage [ "" "static" "dynamic" ] then linkage
    else throw "package.nix: linkage must be \"\", \"static\" or \"dynamic\", not ${toString linkage}";

# Exclude generated and developer state; keep upstream source, tests and release metadata.
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

# Use patchelf on non-Darwin targets to remove Zig cache RPATHs.
isElfTarget = !stdenv.hostPlatform.isDarwin;
in

# Reject Nix cross builds; this derivation targets the native system.
assert stdenv.buildPlatform.system == stdenv.hostPlatform.system;

stdenv.mkDerivation {
  pname = "sqlite3";
  version = "3.53.4";

  inherit src;

  strictDeps = true;
  dontPatch = true;

  # Only installPhase runs Zig, avoiding a second build from generic phases.
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ zig ] ++ lib.optional isElfTarget patchelf;

  # Propagate the C library; build.zig names separate target libraries as needed.
  propagatedBuildInputs = [ stdenv.cc.libc ];

  doCheck = false;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches under TMPDIR, outside the read-only source tree.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"

    # build.zig owns compile flags and install layout.
    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      ${lib.optionalString (requestedLinkage != "") "-Dlinkage=${requestedLinkage}"}

    # Remove Zig build-cache RPATHs while retaining relative and store paths.
    # Resolve symlinks before patching so soname links still point to the object.
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

  # build.zig defines the output layout: library, headers, shell, pkg-config and licence records.
  # Static and shared variants differ only in the library artifact.

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