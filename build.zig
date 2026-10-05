// SPDX-License-Identifier: LicenseRef-PublicDomain
// See FORK-LICENSE.md for what that identifier covers.
//
//! Zig 0.16 build for SQLite 3.53.4.
//!
//! The library is upstream's own amalgamation, byte for byte: the single
//! `src/sqlite3.c` that `src/sqlite3.c:1-18` describes, built from the
//! `sqlite-amalgamation-3530400.zip` release artefact, together with the two
//! headers upstream installs (`upstream/main.mk:1613-1614`). The command-line
//! shell is upstream's own `src/shell.c`, so this package delivers
//! `bin/sqlite3` as well as the library. Nothing is downloaded, no make, no
//! CMake, no TCL and no autosetup script is executed, and the default mode
//! compiles the amalgamation from this repository rather than linking an
//! installed copy.
//!
//! Upstream reference: the official `sqlite-amalgamation-3530400.zip` release,
//! `src/sqlite3.h:149-151` (`SQLITE_VERSION "3.53.4"`,
//! `SQLITE_VERSION_NUMBER 3053004`, and a `SQLITE_SOURCE_ID` naming Fossil
//! check-in `bf7c7f30031888f4e796e429ab3978879485`), `src/sqlite3.c:1-21`
//! ("This file is an amalgamation of many separate C source files from SQLite
//! version 3.53.4 ... comes from Fossil check-in
//! bf7c7f30031888f4e796e429ab3978879485"), and `upstream/VERSION`, which is
//! the three characters `3.53`. The release digests belong in `UPSTREAM.md`,
//! which the fork's provenance owner writes; this script does not restate one.
//!
//! ## Why the amalgamation and not the canonical source tree
//!
//! `upstream/README.md:279-284` states upstream's own answer: "All of the
//! individual C source code and header files ... can be combined into a single
//! big source file **sqlite3.c** called 'the amalgamation'.  The amalgamation is
//! the recommended way of using SQLite in a larger application." Building the
//! canonical tree instead would mean running `autosetup` (a 63 KiB `jimsh` Tcl
//! script) or the Fossil-generated `Makefile.in`, and the result of that run
//! *is* this file: `upstream/README.md:290` names the generator,
//! `tool/mksqlite3c.tcl`. The amalgamation is not a hand-written stand-in for
//! the generator - it is its checked-in output, shipped in the release archive,
//! with the check-in it came from recorded in its own first comment block.
//!
//! ## No compile options are defined
//!
//! This build defines **no `SQLITE_*` macro at all** on any compile line - not
//! for the library, not for the shell, not for the translation. Every
//! configuration decision is left to `sqlite3.c`'s own detection, and each of
//! the ones that matter is a block of upstream source rather than a claim here:
//!
//!   * **Operating system.** `src/sqlite3.c:16538-16548` selects
//!     `SQLITE_OS_WIN` from `_WIN32`, `WIN32`, `__CYGWIN__`, `__MINGW32__` or
//!     `__BORLANDC__` and `SQLITE_OS_UNIX` otherwise. The amalgamation is one
//!     translation unit containing both the Windows and the Unix VFS; nothing
//!     this build does decides which one compiles.
//!   * **Threading.** `src/sqlite3.c:15106-15111` sets `SQLITE_THREADSAFE` to 1
//!     when nothing defines it, which selects `SQLITE_MUTEX_PTHREADS` on Unix
//!     and `SQLITE_MUTEX_W32` on Windows (`src/sqlite3.c:18417-18425`). So the
//!     delivered library is serialized-mode, multi-thread-safe, and says so
//!     through `sqlite3_threadsafe()`.
//!   * **WASI.** `src/sqlite3.c:11676-11685` detects `__wasi__` and defines
//!     `SQLITE_WASI`, plus `SQLITE_OMIT_LOAD_EXTENSION` and `SQLITE_THREADSAFE
//!     0`. This build therefore needs no WASI exception of its own, and does not
//!     invent one: the same amalgamation, unmodified, is what a `wasm32-wasi`
//!     cell compiles, with the price upstream names and no more.
//!   * **Configuration header.** `src/sqlite3.c:14685` includes
//!     `sqlite_cfg.h`, which exists only when `_HAVE_SQLITE_CONFIG_H` is
//!     defined by a generated configure header. Nothing here generates one, so
//!     the include is not reached - which is upstream's own default, not a
//!     suppression of a diagnostic.
//!
//! What this costs, and states rather than hides: an unconfigured SQLite is
//! SQLite's *default* configuration, which is not the configuration most
//! distributions ship. `PRAGMA compile_options` lists what was left out, and
//! the aggregate this build compiles has no `SQLITE_ENABLE_FTS5`, no
//! `SQLITE_ENABLE_JSON1`, no `SQLITE_ENABLE_MATH_FUNCTIONS`, no
//! `SQLITE_ENABLE_RTREE` and no `SQLITE_ENABLE_COLUMN_METADATA`. A consumer
//! that needs one of those needs a differently configured SQLite, which is a
//! build-time choice and belongs to whoever makes it - this package pins one
//! configuration and says so rather than turning the header surface into
//! something a caller has to discover at run time.
//!
//! ## The three link libraries, and where each comes from
//!
//! SQLite's own `sqlite3.pc.in` records four: `@LDFLAGS_MATH@`,
//! `@LDFLAGS_ZLIB@`, `@LDFLAGS_DLOPEN@`, `@LDFLAGS_PTHREAD@` and
//! `@LDFLAGS_ICU@` in `Libs.private`. This build names three of them and names
//! them per target, from what the amalgamated C actually references rather than
//! from a configure probe this build cannot run:
//!
//!   * `-lm`. `src/sqlite3.c:136436-136437` calls `ceil` and `floor`
//!     unconditionally - they are wrapped in `xCeil`/`xFloor` because "on some
//!     systems, ceil() and floor() are intrinsic function. You are unable to take
//!     a pointer to these functions" (`src/sqlite3.c:136431-136435`) - so the
//!     maths library is a link-time requirement of the default build, on every
//!     platform whose C library keeps the maths separate. `src/shell.c:8201-8202`
//!     does the same, so the shell needs it too. It is not named on Windows,
//!     where the maths are in the C runtime, nor on WASI, whose libc carries
//!     them and has no separate `libm` to name.
//!   * `-ldl`, where `dlopen` lives in a library this build has to name.
//!     `src/sqlite3.c:47240` calls it under `#ifndef SQLITE_OMIT_LOAD_EXTENSION`
//!     (`src/sqlite3.c:47232`), which nothing in this build defines on any target
//!     but WASI - and on WASI upstream's own arm defines it
//!     (`src/sqlite3.c:11679-11681`). On Darwin `dlopen` is in libc; on Windows
//!     the loader is `LoadLibrary` (`src/sqlite3.c:31044`) and needs no library
//!     name.
//!   * `-lpthread`, where `SQLITE_MUTEX_PTHREADS` selects the pthread mutex
//!     implementation: `src/sqlite3.c:30623-30625` includes `<pthread.h>` and
//!     `src/sqlite3.c:23543` takes the pthread arm of the mutex factory. That is
//!     what `SQLITE_THREADSAFE 1` - the default - gives on every Unix target.
//!     Not on Windows (`SQLITE_MUTEX_W32`), not on WASI
//!     (`SQLITE_THREADSAFE 0`).
//!
//! `@LDFLAGS_ZLIB@` is absent because `sqlite3.c` reaches zlib only through
//! `SQLITE_ENABLE_FTS5`'s `fts5` compression and the `sqlite3_` session
//! extension's `SQLITE_ENABLE_SESSION`/external-content paths, none of which
//! this configuration compiles: `grep -c 'zlib.h' src/sqlite3.c` is 0. Naming
//! a `-lz` that nothing references would be a link-line claim with no
//! declaration behind it, and `@LDFLAGS_ICU@` is absent for the same reason
//! (`grep -c 'unicode/ucnv.h' src/sqlite3.c` is 0).
//!
//! ## Static and shared delivery
//!
//! `-Dlinkage` selects which artifact this package produces. Nothing about the
//! compiled C changes between the two: the same one translation unit, the same
//! absence of compile options, the same headers.
//!
//! The soname is upstream's. `upstream/main.mk:1556-1563` installs the shared
//! library as `libsqlite3.so.$(PACKAGE_VERSION)` with symlinks `libsqlite3.so`
//! and `libsqlite3.so.0`, and `upstream/main.mk:1516-1519` says why the `0`
//! link is there at all: "The link named libsqlite3.so.0 is provided in an
//! attempt to reduce downstream disruption when performing upgrades from
//! pre-3.48 to a version 3.48 or higher." So the ABI name is `libsqlite3.so.0`
//! and `abi_version` below takes 0 for its major.
//!
//! One field cannot produce both of upstream's names, and this build says which
//! one it keeps rather than letting a consumer discover it. Zig's
//! `Compile.version` is a single triple from which it derives the file name
//! (`libsqlite3.so.MAJOR.MINOR.PATCH`) and the soname
//! (`libsqlite3.so.MAJOR`); upstream's file name is `libsqlite3.so.3.53.4` and
//! its soname is `libsqlite3.so.0`, which are not derivable from one triple.
//! The soname is the field that a consumer binary records in `DT_NEEDED` and
//! the field that has to agree with every other SQLite on the machine, so that
//! is the one this build matches: the delivered object is
//! `libsqlite3.so.0.53.4` with soname `libsqlite3.so.0`, where upstream's file
//! name would be `libsqlite3.so.3.53.4`. A C consumer writes `-lsqlite3`, which
//! resolves to the unversioned name in both cases.
//!
//! ELF shared libraries export the whole `sqlite3_*` namespace, including the
//! header-declared `sqlite3_version` data object (`src/sqlite3.h:188`) without a
//! separate function catalogue. Windows uses the `SQLITE_API` decoration the
//! header already spells out (`src/sqlite3.h:72-74`), which is empty by default
//! and is what upstream's own `Makefile.msc` relies on; no module-definition
//! file is generated, because this header declares no symbol the compiler would
//! not export for itself.
//!
//! There is no version script, and the reason is upstream's own header.
//! `src/sqlite3.h:26-31` is the authority on what is API: "If a C-function,
//! structure, datatype, or constant definition does not appear in this file,
//! then it is not a published API of SQLite, is subject to change without
//! notice, and should not be referenced by programs that use SQLite." Every
//! declaration the header carries is exported, and so is every internal symbol
//! the amalgamation defines, which is what a `.so` built from one translation
//! unit would contain anyway. The lua SDK restricts its export surface with a
//! version script because Lua has internal namespaces (`luaS_*`, `luaC_*`) a
//! consumer should not reach; SQLite's one translation unit makes that a
//! different kind of problem, and the honest answer is stated rather than
//! pretended away.
//!
//! ## The test suite this package retains, and the one it does not run
//!
//! The amalgamation archive carries no tests at all - it is four files, and
//! `unzip -l` says so. SQLite's own test suite lives in the *full source*
//! archive of the same release, and `test/` is vendored from
//! `sqlite-src-3530400.zip` whole: 1285 files, the TCL suite (1190 `*.test`
//! files, 32 `*.tcl`), 32 standalone C test tools - `test/atrc.c`,
//! `test/threadtest1.c`, `test/c/changeblob1.c`, `test/wordcount.c` and their
//! companions, none of which is the TCL harness - and the ten `.db` inputs,
//! eight of them the generated `fuzzdata*.db`. Nothing is dropped and nothing is
//! edited; `UPSTREAM.sha256` records every file and `tools/check-provenance.sh`
//! fails if the set changes.
//!
//! The TCL harness's own C sources are in none of that. They live in upstream's
//! canonical `src/` directory, which the full-source archive carries and this
//! package does not vendor: upstream's Fossil manifest for this check-in names
//! `src/tclsqlite.c` and `src/test_sqllog.c`, and it names no
//! `test/testfixture.c` and no `test/sqllog.c`. Neither named file exists in
//! this tree.
//!
//! This package does **not** build or run that suite, and no step pretends
//! otherwise. `test/testrunner.tcl:41-49` drives the suite through a
//! `testfixture` binary, and upstream builds that binary at
//! `upstream/main.mk:1799` from `$(TESTFIXTURE_SRC)`, which
//! `upstream/main.mk:1796-1797` defines as `$(TESTSRC)` plus the generated
//! `tclsqlite-ex.c` plus `sqlite3.c`, the amalgamation, at upstream's default
//! `USE_AMALGAMATION = 1`; at 0 it takes `$(TESTSRC2)` and
//! `$(libsqlite3.LIB)` instead (`upstream/main.mk:1794-1795`). `$(TESTSRC)` is
//! the `$(TOP)/src/test*.c` and `$(TOP)/ext/...` list of
//! `upstream/main.mk:722-810`, and `tclsqlite-ex.c` is generated rather than
//! checked in: `upstream/main.mk:1664-1670` builds it from `$(TCLSQLITEEX)` -
//! `$(TOP)/ext/qrf/qrf.h`, `$(TOP)/ext/qrf/qrf.c` and `$(TOP)/src/tclsqlite.c` -
//! with `$(TOP)/tool/mkcombo.tcl`. That closure is upstream's canonical source
//! tree, and `upstream/Makefile.in:347`, which is `include $(TOP)/main.mk`, is
//! what makes it one build. Running the suite would mean re-introducing exactly
//! the build system this package replaces: `autosetup`, `main.mk`, a TCL 8.6
//! installation and the canonical `src/` and `ext/` trees. So `build.zig` has no
//! `upstream-test` step, fetches nothing to stand in for one, and
//! `README.zig.md` records which independent known answers and which upstream
//! interop check the package's own gates use instead.
//!
//! ## Entry points
//! -----------
//!   zig build           install the library, the two public headers, the
//!                        `sqlite3` program, the relocatable `sqlite3.pc`, and
//!                        the licence and provenance records; and compile the
//!                        example
//!   zig build test      run the behavioural tests for the selected target
//!                        (`-Dtarget`; the host when it is absent)
//!   zig build smoke     run the example program
//!   zig build oracle    run upstream's own `sqlite3` shell over
//!                        `tools/fixture/aggregate.sql` and compare its output
//!                        byte for byte with `tools/fixture/expected.tsv`
//!   zig build consumer  build the separate `consumer/` package, and run it when
//!                        this host can execute the selected target
//!   zig build check     compile the native library, the facade, the tests, the
//!                        example and the shell for all six check targets,
//!                        running nothing
//!
//!   cross-test          the same `test` step, for the published 53-platform
//!                        Zig 0.16.0 Tier 1/2 table rather than the host alone.
//!                        `cross-test` discovers `cross-test.profile.sh` from
//!                        the package root, runs `zig build test -Dtarget=TARGET`
//!                        for each of them, and executes the binary where a
//!                        runner exists and records explicit `build_only`
//!                        coverage where one does not.
//!
//! ## Options
//! -------
//!   -Dlinkage=static   a static archive, `libsqlite3.a`. This is the default.
//!   -Dlinkage=dynamic  a real shared object with upstream's `libsqlite3.so.0`
//!                      ABI name.
//!   -Druntime=true     resolve the native entry points at run time instead of
//!                      linking them. Orthogonal to `-Dlinkage`, which still
//!                      decides which artifact this build delivers and installs.
//!                      Default off; a linked build is unchanged.
//!   -Dsystem=true      link an installed `libsqlite3` instead of compiling
//!                      `src/`. Supplies the default of
//!                      `b.systemIntegrationOption("sqlite3", ...)`; a build
//!                      runner that decides the mode itself (`-fsys=sqlite3`)
//!                      overrides it. Not gated in this wave.
//!   -Dtarget=<triple>  build for one target; `zig build check` then checks
//!                      that target only instead of the whole matrix.
//!   -Doptimize=<mode>  the caller's mode, passed to every graph below.
//!
//! ## No target is refused
//!
//! Unlike a Lua or a WASI-bound graph, this one has no refusal list and no
//! `refused_check_targets`: all six targets are walked by `check`, and the
//! configuration each one is given is in `Platform`. That is not a claim that
//! all six build - it is the opposite: nothing here drops a row, and the gate
//! that decides is `zig build check`. The one thing refused is a *delivery*
//! rather than a target: `deliveredLinkage` stops a `-Dlinkage=dynamic` on a
//! target whose OS has no dynamic linker, naming the target and the way out.
//! See "Static and shared delivery".

const std = @import("std");

/// The runtime-loading build half, owned by the API role.
///
/// `createModule` builds the generated dispatch that replaces
/// `translate.createModule()` under `-Druntime`; it makes the loader-core
/// module itself and re-exports `LoadSource`/`LoadError` from it.
/// `createCoreModule` builds that same core module for the *linked* branch,
/// where there is no dispatch to carry the types and the facade's `rt` import
/// is where they come from.
///
/// The two branches must not both call `createCoreModule`. `LoadSource` and
/// `LoadError` are this SDK's public types, so they have to be the *same*
/// types in one build: a second core instance would be a second, nominally
/// distinct `LoadSource`, and `sqlite.load(source)` would be handing the
/// facade's type to a function expecting the dispatch's. `add_graph` is the only
/// place that calls either of them.
const graph = @import("runtime/graph.zig");

/// `build.zig.zon` itself. `@import` of the manifest is how a build script
/// reads `.version` without a second copy of it.
const manifest = @import("build.zig.zon");

/// `build.zig.zon .version`, parsed. The parse is the loud part: a manifest
/// whose `.version` is not a semantic version fails to configure here rather
/// than being silently compared as something else.
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

/// Package id, the name a dependent writes in its dependency map, the one
/// registered module and the C artifact.
///
/// They are one name on purpose, and it is upstream's rather than the
/// directory's: `dep.module("sqlite3")` and `dep.artifact("sqlite3")` describe
/// the same library, and `libsqlite3.a` is what Zig emits for an artifact called
/// `sqlite3` because `std.zig.system` prepends the platform's `lib` prefix.
/// That is the file name upstream's own build produces (`upstream/main.mk`) and
/// the one a C consumer's `-lsqlite3` needs - upstream's own
/// `sqlite3.pc.in` names `-lsqlite3` - so a C consumer of this package writes
/// the same link line it would write against an upstream build. The repository
/// directory is `sqlite/`; the package name is the C library's.
const lib_name = "sqlite3";

/// The Zig facade. It re-exports the translated module as `c`.
const facade_source = "zig/root.zig";

/// The one header this package translates. It is a fork-authored wrapper whose
/// whole job is to name the public header upstream's C consumers include; see
/// the file for why it is a wrapper and not a copy.
const translate_header = "zig/translate.h";

/// Test root, owned by the API role.
const test_source = "tests.zig";

/// The deterministic example program, owned by the API role.
const example_source = "smoke.zig";

/// Where the native source lives.
const source_dir = "src";

/// Upstream's version, read out of `src/sqlite3.h:149` and confirmed against
/// `upstream/VERSION`, which is the three characters `3.53`. It is the version
/// of the C library this package builds, and `build.zig.zon .version` carries
/// the same string; `build` refuses to configure when the two drift apart, so
/// the pkg-config `Version:` field, the shared object's file name and the
/// package manifest cannot describe three different releases.
const upstream_version: std.SemanticVersion = .{ .major = 3, .minor = 53, .patch = 4 };

/// The shared object's ABI version. See "Static and shared delivery" above: the
/// major is upstream's own `libsqlite3.so.0`
/// (`upstream/main.mk:1556-1563`, and `:1516-1519` for why that name is kept),
/// and the minor and patch are the release this build compiles.
const abi_version: std.SemanticVersion = .{ .major = 0, .minor = 53, .patch = 4 };

/// The one C translation unit of the library.
///
/// `src/sqlite3.c:1-18` is upstream's own description of what the file is: "This
/// file is an amalgamation of many separate C source files ... This file is all
/// you need to compile SQLite." There is no source list to trim and no unit to
/// add: the archive carries one `.c` file for the library.
const core_sources = [_][]const u8{
    "src/sqlite3.c",
};

/// The shell program's own main, and the name upstream gives its result.
///
/// `upstream/main.mk` builds `$(libsqlite3.DLL)` from the amalgamation and the
/// `sqlite3` shell from `$(TOP)/shell.c`; this package ships the amalgamated
/// shell as `src/shell.c` because that is the form the release archive carries,
/// and `src/shell.c` is the same file `upstream/main.mk` names.
const Program = struct {
    /// The program.
    name: []const u8,
    /// Its `main`.
    source: []const u8,
};

/// `sqlite3`, the command-line shell.
const shell: Program = .{ .name = "sqlite3", .source = "src/shell.c" };

/// The two headers upstream installs.
///
/// `upstream/main.mk:1613-1614` is the whole list:
/// `install-headers: sqlite3.h $(install-dir.include)` followed by
/// `$(INSTALL.noexec) sqlite3.h "$(TOP)/src/sqlite3ext.h" "$(install-dir.include)"`.
///
/// `sqlite3ext.h` is installed and not translated; `zig/translate.h` says why in
/// the file, and `runtime/graph.zig` repeats it where the router is configured.
const public_headers = [_][]const u8{
    "src/sqlite3.h",
    "src/sqlite3ext.h",
};

/// The licence and provenance records `zig build` installs under
/// `share/licenses/sqlite/`.
///
/// SQLite's term is a public-domain dedication rather than a permissive licence,
/// and upstream keeps it in two places in this tree rather than in one: the
/// blessing at the head of every source file (`src/sqlite3.h:1-8`,
/// `src/sqlite3.c` carries the same block) and `upstream/LICENSE.md`, which is
/// the same dedication written as prose. Both install, because a package that
/// ships a binary and neither text has removed an obligation a private
/// repository does not remove. The rest are this fork's records.
///
/// `share/licenses/sqlite` is the location both this build and `package.nix`
/// use, which is what lets the packaging layer's own `install -Dm644` be an
/// idempotent overwrite of these bytes rather than a second copy.
const licence_records = [_][]const u8{
    "upstream/LICENSE.md",
    "src/sqlite3.h",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "UPSTREAM.sha256",
    "FORK-NOTES.md",
    "CHANGELOG.md",
};

/// Language level for every C translation unit, pinned.
///
/// SQLite states no dialect requirement anywhere in this tree: `src/sqlite3.c`
/// carries no `-std=` line and no configure probe for one, and its C is C89-era
/// code that every later dialect accepts. Pinning the level means it is a fact
/// of this build rather than a fact about the host clang, and `gnu11` is the
/// lowest dialect that defines every facility the amalgamation actually uses -
/// `//`-comments, `_Bool`, `<stdint.h>` types and anonymous unions. It is
/// deliberately *not* a maximum: no dialect flag here can change which upstream
/// source files compile, because upstream compiles them all in one unit.
const c_flags = [_][]const u8{"-std=gnu11"};

/// Which `libsqlite3` the package links.
const Library = enum {
    /// Compiled from the pinned upstream amalgamation in `src/`.
    bundled,
    /// The installed library `systemIntegrationOption("sqlite3")` selected.
    system,
};

/// The cross-compilation matrix `check` walks when no target is named.
///
/// The order is the one this workspace uses everywhere, and all six rows are
/// here - see "No target is refused" in the module comment. Nothing is skipped
/// and nothing is pre-judged: a target that cannot be satisfied on the machine
/// running the gate is for the gate to report, and the honest response to a
/// failing cell is a diagnosis recorded in `FORK-NOTES.md`, never a row removed
/// from this list.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// The name one program artifact carries in this build graph.
///
/// The published graph installs `bin/sqlite3`, the name `upstream/main.mk` and
/// `sqlite3.pc.in` give it, and a check graph installs nothing, so its artifacts
/// carry the target triple instead: six targets share one build graph, and six
/// steps all called `sqlite3` make `--summary all` impossible to read.
fn programName(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    base: []const u8,
    public: bool,
) []const u8 {
    if (public) return base;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}-{s}", .{ base, lib_name, triple });
}

/// What one target's platform configuration is.
///
/// Resolved from the target being built, never from the build host, and read by
/// the library, the translation, the shell and the configure line so that one
/// fact is in one place.
const Platform = struct {
    /// The `SQLITE_*` macros this target's compile line carries.
    ///
    /// Empty on every target, and that is the point rather than an omission: see
    /// "No compile options are defined" in the module comment for the four
    /// upstream blocks that make the decisions instead. The field exists so that
    /// a future release that needs one has a place to put it and so that a
    /// reader can see the answer is a decision rather than an oversight.
    macros: []const [2][]const u8,
    /// Whether `ceil`/`floor` live in a library this build has to name. They are
    /// called unconditionally at `src/sqlite3.c:136436-136437`, so this is
    /// `false` only where the C library carries the maths itself: Windows' C
    /// runtime, and WASI's libc, which has no separate `libm`.
    separate_m: bool,
    /// Whether `dlopen` lives in a library this build has to name
    /// (`src/sqlite3.c:47240`).
    separate_dl: bool,
    /// Whether `SQLITE_MUTEX_PTHREADS` brings in pthread, which needs naming
    /// (`src/sqlite3.c:30623-30625`).
    separate_pthread: bool,
    /// Whether `__declspec` exists on this target. It is recorded rather than
    /// used: `SQLITE_API` is an empty macro by default (`src/sqlite3.h:72-74`),
    /// so a shared Windows build needs no export decoration from this package.
    dll: bool,
    /// The WASI emulation switches a *program* has to compile with, paired with
    /// the library that carries each one. Empty on every target but WASI.
    ///
    /// `src/shell.c` includes `<signal.h>` (`:170`), takes `<sys/resource.h>`
    /// in through `<sys/time.h>` and calls `getrusage` (`:24782`, `:24810`) and
    /// `getpid` (`:36573`, through `GETPID` at `:178`). WASI has none of the
    /// three, and this toolchain's wasi-libc answers each of those headers with
    /// an `#error` that names both the switch and the library. The file is
    /// upstream's and is not edited, so the answer is a compile-line fact.
    ///
    /// This is deliberately not part of `kind()`: the printed configuration
    /// line is about the library, which needs none of it - `src/sqlite3.c` does
    /// not include any of those headers, and its WASI arm
    /// (`src/sqlite3.c:11676-11685`) already compiles.
    wasi_emulation: []const [2][]const u8,

    fn forTarget(target: std.Build.ResolvedTarget) Platform {
        const os_tag = target.result.os.tag;
        if (os_tag == .windows) {
            // `src/sqlite3.c:16540-16543` selects `SQLITE_OS_WIN` from `_WIN32`
            // and the compiler this build uses predefines it; the mutex
            // implementation is `SQLITE_MUTEX_W32`
            // (`src/sqlite3.c:18422-18423`), so there is no pthread, and the
            // dynamic loader is `LoadLibrary` from the C runtime
            // (`src/sqlite3.c:31044`). The maths are in the same runtime.
            return .{
                .macros = &.{},
                .separate_m = false,
                .separate_dl = false,
                .separate_pthread = false,
                .dll = true,
                .wasi_emulation = &.{},
            };
        }
        if (os_tag == .wasi) {
            // Upstream's own `__wasi__` arm (`src/sqlite3.c:11676-11685`) sets
            // `SQLITE_OMIT_LOAD_EXTENSION` and `SQLITE_THREADSAFE 0`, so there is
            // no `dlopen` to name and no pthread to name. `ceil`/`floor` are
            // still called, and wasi-libc carries them in the C library itself:
            // this toolchain's WASI sysroot ships one `libc.a` and no separate
            // maths archive, so `-lm` has nothing to resolve to. Nothing here is
            // defined by this build; see the module comment.
            return .{
                .macros = &.{},
                .separate_m = false,
                .separate_dl = false,
                .separate_pthread = false,
                .dll = false,
                .wasi_emulation = &.{
                    .{ "_WASI_EMULATED_SIGNAL", "wasi-emulated-signal" },
                    .{ "_WASI_EMULATED_PROCESS_CLOCKS", "wasi-emulated-process-clocks" },
                    .{ "_WASI_EMULATED_GETPID", "wasi-emulated-getpid" },
                },
            };
        }
        if (os_tag.isDarwin()) {
            // `dlopen` and `pthread_create` are both in Darwin's libc, so only
            // the maths need naming.
            return .{
                .macros = &.{},
                .separate_m = true,
                .separate_dl = false,
                .separate_pthread = false,
                .dll = false,
                .wasi_emulation = &.{},
            };
        }
        // Every other Unix - Linux, the BSDs, Solaris, illumos, AIX - gets the
        // three libraries `src/sqlite3.c` references there: the maths wrappers
        // (`:136436-136437`), the `dlopen` in the extension loader
        // (`:47232-47240`) and the pthread mutex the default `SQLITE_THREADSAFE
        // 1` selects (`:15106-15111`, `:18417-18421`, `:30623-30625`).
        return .{
            .macros = &.{},
            .separate_m = true,
            .separate_dl = true,
            .separate_pthread = true,
            .dll = false,
            .wasi_emulation = &.{},
        };
    }

    /// One line naming this platform configuration, for the configure-time
    /// output. It reads what `forTarget` resolved rather than deciding anything
    /// of its own, so the printed line cannot disagree with what was compiled.
    fn kind(platform: Platform) []const u8 {
        if (platform.macros.len != 0) return "a platform macro this build defines";
        if (platform.separate_m and platform.separate_dl and platform.separate_pthread)
            return "upstream's own detection: -lm -ldl -lpthread";
        if (platform.separate_m)
            return "upstream's own detection: -lm";
        return "upstream's own detection: no separate link library";
    }
};

/// One target's library and facade.
const Graph = struct {
    /// The compiled C library, or null in system mode, where nothing is
    /// compiled from this tree.
    c_lib: ?*std.Build.Step.Compile,
    /// The facade module, with `c` bound to the translated headers for the
    /// library this graph compiled or selected.
    module: *std.Build.Module,
    /// The platform this graph compiled for, so a caller that adds a program
    /// does not resolve the target a second time and risk disagreeing.
    platform: Platform,
};

/// The name a compiled artifact carries in this build graph.
///
/// The published graph installs `libsqlite3.a`, the name a C consumer's
/// `-lsqlite3` needs. A check graph installs nothing, so its artifacts carry the
/// target triple instead: six targets share one build graph, and six steps all
/// called `sqlite3` make `--summary all` impossible to read.
fn artifactName(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    public: bool,
) []const u8 {
    if (public) return lib_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}", .{ lib_name, triple });
}

/// Builds one target's library and facade.
///
/// `public` chooses between the package module set, which is what a dependent
/// reaches through `dep.module("sqlite3")`, and a private module. A cross-target
/// check needs the private form: modules are registered by name against the
/// whole build, so registering `sqlite3` once per matrix target would leave only
/// the last of them reachable and silently stop checking the rest. The
/// translated headers are imported rather than registered in both forms; the
/// published routes are named above.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    library: Library,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    public: bool,
) Graph {
    // Every route into this file passes through here: `build` for the published
    // graph and for `-Dtarget=`, and `add_target_check` for each matrix cell.
    // `runConsumer` reaches it too, one process later: it shells out to a
    // nested `zig build` in `consumer/` that resolves this package as a
    // dependency, and that nested build runs this `build()`.
    const platform = Platform.forTarget(target);

    const c_lib: ?*std.Build.Step.Compile = if (library == .bundled)
        add_c_library(b, target, optimize, linkage, platform, artifactName(b, target, public))
    else
        null;

    // The linkage this target can actually carry, resolved here so the
    // translation and the library cannot disagree about it. `add_c_library`
    // resolves the same value for the same reason.

    // Everything the translation is given, resolved once, because both routes
    // have to see the same thing. System mode contributes nothing, for the reason
    // the include path comment below gives: there the installed headers are the
    // ones the translation describes.
    const no_macros: []const [2][]const u8 = &.{};
    const translate_macros = if (library == .bundled) platform.macros else no_macros;
    const translate_include: ?std.Build.LazyPath =
        if (library == .bundled) b.path(source_dir) else null;

    const translate = b.addTranslateC(.{
        .root_source_file = b.path(translate_header),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    if (translate_include) |dir| {
        // `zig/translate.h` includes `<sqlite3.h>`, and this is the only header
        // search path the translation has. Without it the translation would bind
        // to whatever SQLite happens to be installed on the build machine and
        // describe that library's declarations rather than the ones this graph
        // compiles (`WISDOM.md` W14). System mode deliberately does not add it:
        // there the same line is reached through the installed prefix's include
        // directory, never through this tree - see "system mode" below.
        translate.addIncludePath(dir);
    }
    // The same platform macros the C was compiled with, on the translation too.
    // On every target in this package that list is empty, and that is the
    // decision: a translation that resolved a different configuration from the
    // compiled C would describe a library this build does not produce.
    for (translate_macros) |macro| translate.defineCMacro(macro[0], macro[1]);

    // System mode: the installed `sqlite3.pc` names the library this translation
    // binds, and one query gives it to both. `createModule` carries the entry
    // onto the `c` module below, so a dependent compiles and links against the
    // same prefix the declarations were read from.
    //
    // What system mode cannot do is point the *translation* at the installed
    // headers, because the include directory `sqlite3.pc` names is not an
    // include path this build can read from a `.pc` file it is not executing.
    // `-Dsystem=true` is therefore correct only where the installed `sqlite3.h`
    // is on the compiler's default search path, and that is `WISDOM.md` W14
    // exactly: the real fix is a recorded, verified header and ABI version, and
    // no gate in this wave runs this mode. It is present because a dependent's
    // build runner can ask for it, not because it is a checked configuration.
    if (library == .system) {
        translate.linkSystemLibrary(lib_name, .{ .preferred_link_mode = linkage });
    }

    const module = if (public)
        b.addModule(lib_name, .{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
    // Where the runtime-loading seam is
    // ---------------------------------
    // `runtime/graph.zig`, which the API role owns, exposes
    //
    //     pub fn createModule(
    //         b: *std.Build,
    //         translate: *std.Build.Step.TranslateC,
    //         target: std.Build.ResolvedTarget,
    //         optimize: std.builtin.OptimizeMode,
    //     ) *std.Build.Module
    //
    //     pub fn createCoreModule(
    //         b: *std.Build,
    //         target: std.Build.ResolvedTarget,
    //         optimize: std.builtin.OptimizeMode,
    //     ) *std.Build.Module
    //
    // and `-Druntime` substitutes the first for `translate.createModule()`. It
    // takes the `TranslateC` step this function has already built, so the
    // generated dispatch keeps the exact translated type and constant namespace
    // rather than compiling a second copy of the native extern declarations and
    // casting between two nominally distinct Zig modules: `c.sqlite3_open_v2` in
    // the facade and the declaration behind the table are one type.
    //
    // `-Dlinkage` is orthogonal and keeps meaning what it means: it selects
    // which artifact this build *delivers* and installs, never which one the
    // module dispatches through.
    //
    // The `rt` import is for the linked branch only, and the reason is the
    // nominal type rather than the code: `graph.createModule` creates the one
    // core-module instance the generated dispatch uses and re-exports
    // `LoadSource`/`LoadError` from it; a second instance created here for the
    // facade would be a *different* `LoadSource`, and `sqlite.load(source)`
    // would be handing the facade's type to a function expecting the dispatch's.
    // One instance per build, no more. In a linked build there is no dispatch, so
    // the facade's own `rt` import is where those two public types come from;
    // `zig/root.zig` picks between the two with a comptime branch on
    // `runtime_loaded`, so the module a configuration does not need is never
    // resolved and never compiled.
    //
    // The shell below is *not* affected by `-Druntime`. It is upstream's own C,
    // compiled from this repository, and it links whatever `-Dlinkage`
    // delivered; the option selects the dispatch of the Zig facade, not how the
    // native shell is built.
    if (runtime_loaded) {
        // A loaded provider must arrive through the platform loader, so the
        // link line names nothing. Linking the archive as well would make the
        // linker resolve the same symbols statically and the runtime route
        // would quietly be a linked one. The artifact itself is still built and
        // installed, because delivery and dispatch are separate questions: the
        // whole point of the mode is that a caller may name a provider this
        // tree did not build.
        module.addImport("c", graph.createModule(b, translate, target, optimize));
    } else {
        // The translated headers are imported, never registered.
        // `addModule("c")` would make `dep.module("c")` resolve and hand a
        // dependent the same declarations without the library that satisfies
        // them; the facade's own `c` import is the supported way in and carries
        // the facade's linkage.
        module.addImport("c", translate.createModule());
        module.addImport("rt", graph.createCoreModule(b, target, optimize));
        // System mode names the installed library through the translation above,
        // so this module already carries it.
        if (c_lib) |lib| module.linkLibrary(lib);
    }

    // The same include path as the archive's own module, on the module a
    // dependent actually imports, so a dependent that compiles its own C
    // against this package finds the same headers the core was compiled with.
    // System mode does not add it: the installed include directory reaches the
    // dependent through the same `sqlite3.pc` entry.
    if (library == .bundled) module.addIncludePath(b.path(source_dir));

    return .{ .c_lib = c_lib, .module = module, .platform = platform };
}

/// Compiles the C library for one target: the amalgamation, and nothing else.
///
/// `requested` is the linkage the caller asked for. What it selects is the
/// artifact and nothing else about the compilation. What a shared artifact adds
/// is its own requirements - the soname and PIC - and `delivered` is what this
/// target can actually carry.
///
/// `name` is the artifact name this graph installs or reports; see
/// `artifactName`.
fn add_c_library(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    requested: std.builtin.LinkMode,
    platform: Platform,
    name: []const u8,
) *std.Build.Step.Compile {
    const linkage = deliveredLinkage(target, requested);
    const c_lib = b.addLibrary(.{
        .name = name,
        .linkage = linkage,
        // See "Static and shared delivery" for where `abi_version` comes from
        // and for the one file name it cannot also produce.
        // `version` is null for a static archive, which has no soname and no
        // versioned file name.
        .version = if (linkage == .dynamic) abi_version else null,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            // libc, and for the reason the amalgamation itself gives: `src/shell.c`
            // is the only other unit, and the library reaches the C library for
            // its own vocabulary in one place or another - `<stdlib.h>` at
            // `src/sqlite3.c:15670` for malloc and free, `<string.h>` at `:15671`
            // for memcpy, `<math.h>` at `:36409` for the maths wrappers at
            // `:136436-136437`, `<time.h>` at `:25509` for its timestamps,
            // `<pthread.h>` at `:30625` for the default mutex, `<unistd.h>` at
            // `:40291` for the Unix VFS, `<sys/mman.h>` at `:40297` for its
            // memory mapping, and `<dlfcn.h>` at `:47237` for the extension
            // loader.
            .link_libc = true,
            // A shared library is position-independent whether or not this says
            // so; naming it makes the requirement explicit.
            .pic = if (linkage == .dynamic) true else null,
        }),
    });
    const c_mod = c_lib.root_module;

    // For the sources' own quoted includes: `src/sqlite3.c:356` includes
    // `<stdarg.h>` and its embedded copy of `sqlite3.h` by bare name in a few
    // places, and `src/shell.c:158` includes `"sqlite3.h"`.
    c_mod.addIncludePath(b.path(source_dir));

    // The platform configuration for the target being built, not for the host.
    // `addGraph` gives the translation the same list. Empty on every target in
    // this package - see "No compile options are defined" in the module comment
    // for why that is the answer and not a gap.
    for (platform.macros) |macro| {
        c_mod.addCMacro(macro[0], macro[1]);
    }

    for (core_sources) |source| {
        c_mod.addCSourceFile(.{
            .file = b.path(source),
            .flags = &c_flags,
        });
    }

    // The three libraries the amalgamated C actually references; see the module
    // comment for the line each one is read out of.
    //
    // `linkSystemLibrary` takes its `LinkSystemLibraryOptions` explicitly and
    // has no defaults for the call, so the empty options struct is the shape
    // here: `needed`, `weak`, `use_pkg_config`, `preferred_link_mode` and
    // `search_strategy` all keep the values `LinkSystemLibraryOptions` declares
    // (`lib/std/Build/Module.zig:344-361`). For `-lm`, `-ldl` and `-lpthread`
    // that is what is wanted - C library names, not pkg-config packages, so
    // `use_pkg_config` has nothing to ask for and the dynamic preference is the
    // right one.
    if (platform.separate_m) c_mod.linkSystemLibrary("m", .{});
    if (platform.separate_dl) c_mod.linkSystemLibrary("dl", .{});
    if (platform.separate_pthread) c_mod.linkSystemLibrary("pthread", .{});

    // Installing the headers also puts them on the include path of anything that
    // links this artifact, so a C consumer needs nothing from this tree to call
    // it. These two are the whole of upstream's installed header list.
    for (public_headers) |header| {
        c_lib.installHeader(b.path(header), std.fs.path.basename(header));
    }

    return c_lib;
}

/// The `sqlite3` shell for one target.
///
/// It follows the delivered linkage, so `-Dlinkage=dynamic` gives a `sqlite3`
/// that loads `libsqlite3.so.0` and a static build gives the one upstream's own
/// make produces when the shared library is switched off.
///
/// Two things about `src/shell.c` are worth naming because they decide what this
/// program's module has to carry:
///
///   * It is the oracle for `zig build oracle`. `tools/fixture/aggregate.sql` is
///     run through this program and its output compared byte for byte with
///     `tools/fixture/expected.tsv`, which is upstream's own C client and its own
///     SQL front end answering the same question the facade answers in
///     `tests.zig`. That is the upstream interop fixture; it is separate from the
///     hand-computed known answers, and neither is derived from the other.
///   * It includes `<math.h>` (`src/shell.c:156`) and calls `ceil`/`floor`
///     (`src/shell.c:8201-8202`), so it needs the same `-lm` the library does. It
///     also uses `<dirent.h>` (`src/shell.c:177`), `<sys/stat.h>` (`:189`),
///     `<unistd.h>` (`:176`), `<sys/ioctl.h>` (`:166`) and `<signal.h>` (`:170`)
///     on the non-Windows path, and `<windows.h>` (`:282`) on the Windows one -
///     all libc, all reached through the module below.
fn add_program(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    platform: Platform,
    c_lib: *std.Build.Step.Compile,
    program: Program,
    name: []const u8,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // No `pic` here. A shared library is position-independent because its
        // own module says so (`add_c_library`), and an executable that links one
        // is not required to be.
    });
    mod.addIncludePath(b.path(source_dir));
    for (platform.macros) |macro| mod.addCMacro(macro[0], macro[1]);

    mod.addCSourceFile(.{
        .file = b.path(program.source),
        .flags = &c_flags,
    });
    // The same options and the same reason as `add_c_library`: `-lm`, `-ldl`
    // and `-lpthread` are C library names, not pkg-config packages.
    if (platform.separate_m) mod.linkSystemLibrary("m", .{});
    if (platform.separate_dl) mod.linkSystemLibrary("dl", .{});
    if (platform.separate_pthread) mod.linkSystemLibrary("pthread", .{});
    // WASI carries no signals, no process-associated clocks and no process
    // identifier, and upstream's shell uses all three (`src/shell.c:170`,
    // `:24782`, `:24810`, `:36573`). `Platform` names the switch each missing
    // header asks for together with the library that provides it; both halves
    // are needed, because the header's `#error` fires without the switch even
    // though the library is linked.
    for (platform.wasi_emulation) |emulation| {
        mod.addCMacro(emulation[0], "1");
        mod.linkSystemLibrary(emulation[1], .{});
    }
    mod.linkLibrary(c_lib);
    // An installed shared library sits in `lib/` and an installed program in
    // `bin/`, so a program linked against it needs the loader to look beside
    // itself. `addRPathSpecial` is the only way to say a relative `$ORIGIN`
    // rpath: a `LazyPath` here would be resolved against the build cache, which
    // is not where the installed file is.
    if (linkage == .dynamic) {
        if (installedRPath(target)) |rpath| mod.addRPathSpecial(rpath);
    }

    return b.addExecutable(.{ .name = name, .root_module = mod });
}

/// The rpath an installed program in this package needs, or null where the
/// object format has none.
///
/// `bin/sqlite3` and `lib/libsqlite3.so.0` are siblings under one prefix, so
/// `$ORIGIN/../lib` is the ELF spelling and `@loader_path/../lib` the Mach-O
/// one. COFF has neither: `b.installArtifact` puts a DLL in `bin/` beside the
/// program, which is where its loader looks.
fn installedRPath(target: std.Build.ResolvedTarget) ?[]const u8 {
    return switch (target.result.ofmt) {
        .elf => "$ORIGIN/../lib",
        .macho => "@loader_path/../lib",
        else => null,
    };
}

/// Compiles the full graph, the tests, the example and the shell for one matrix
/// target and attaches all of them to `step`.
///
/// Building the test binary and the example is what makes this a check of the
/// facade rather than of an unreferenced archive: Zig analyses a function body
/// only when something calls it, and `tests.zig` and `smoke.zig` call the
/// facade. The whole amalgamated closure and the shell's 37 415 lines are
/// compiled by the same graph, so a target that cannot build SQLite fails here
/// rather than at the first install. Nothing is run here, so every result this
/// step produces is compile evidence and not a claim that a cross-built binary
/// executed.
fn add_target_check(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    library: Library,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
) void {
    const cross_target = b.resolveTargetQuery(query);
    // The triple names the cross artifacts. Six targets in one build graph
    // otherwise produce six steps called "sqlite3", which makes `--summary all`
    // useless for telling them apart.
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("unspellable target");

    const cross = addGraph(b, cross_target, optimize, library, linkage, runtime_loaded, false);

    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addTest(.{
        .name = b.fmt("sqlite3-tests-{s}", .{triple}),
        .root_module = test_mod,
    }).step);

    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addExecutable(.{
        .name = b.fmt("sqlite3-smoke-{s}", .{triple}),
        .root_module = example_mod,
    }).step);

    // The shell is part of what this package delivers, so a target where it does
    // not compile is a target this SDK does not support, and the matrix says so
    // at build time rather than at install. System mode builds neither: there is
    // no local library for it to link.
    if (cross.c_lib) |c_lib| {
        step.dependOn(&add_program(
            b,
            cross_target,
            optimize,
            linkage,
            cross.platform,
            c_lib,
            shell,
            programName(b, cross_target, shell.name, false),
        ).step);
    }
}

/// Runs the consumer package as its own `zig build` in `consumer/`.
///
/// The consumer is a separate package on purpose: a manifest dependency here
/// would close a cycle, because its manifest points back at this package by
/// path. Running it as a separate build is what makes the proof real - that a
/// package which only writes `b.dependency("sqlite3", ...)` and
/// `dep.module("sqlite3")` gets a working, correctly linked library, with the
/// archive and libc arriving through the module and nothing else.
///
/// Everything this build resolved travels with it: the target and CPU, the
/// optimize mode, the library mode, the linkage and dispatch shapes, the
/// executor switches, both cache directories, the install prefix, the job width
/// and the summary. An argument left behind would be a proof of a configuration
/// nobody asked for.
///
/// Run when this host can execute the selected target, and install otherwise:
/// `hostCanExecute` asks exactly what `std.Build.Step.Run` asks of a foreign
/// binary, so the decision here and the nested run cannot disagree. An executor
/// counts only when its `-f` switch was given; a target with none installs,
/// which is compile evidence and never a semantic pass.
fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    library: Library,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
) *std.Build.Step.Run {
    const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    // The same query's other half. The triple above names the architecture,
    // the OS and the ABI; it carries no CPU model and no feature set
    // (`lib/std/Target/Query.zig:421-423`), and `cpu` is a separate option of
    // its own (`lib/std/Build.zig:1479-1483`). `serializeCpu`
    // (`lib/std/Target/Query.zig:530`) writes `native` for a query that named
    // no CPU and `baseline` for a cross query that named none, and
    // `Target.Query.parseCpu` recognises both spellings (`:280-283`), so the
    // nested `standardTargetOptions` resolves this build's selection rather
    // than one of its own. `addArg` copies each argument, so these
    // temporaries can go right after.
    const cpu = target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // `b.graph.zig_exe` is the compiler running this build script, so the
    // nested build is the same toolchain rather than whatever is on PATH.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    // The model and its feature set, for the reason the serialization above
    // gives. Without it the nested build would compile the consumer at a
    // baseline CPU on a host that built the library for something else, and
    // the step would prove a configuration nobody asked for.
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    // The delivery and dispatch options have to reach the nested build or the
    // consumer would silently check the default graph and say nothing about the
    // configuration that was asked for.
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));
    // Both spellings go, not only the true one, so a cell's configuration is
    // stated rather than inferred from a default and the flag cannot be dropped
    // on the way down. `consumer/build.zig` reads the option and hands it
    // to `b.dependency("sqlite3", ...)`, and that value is what
    // `consumer/src/main.zig` branches on at comptime.
    run.addArg(b.fmt("-Druntime={s}", .{if (runtime_loaded) "true" else "false"}));
    // The mode *this* build resolved, which is a different question from which
    // option asked for it. `b.systemIntegrationOption` is fed by the build
    // runner's `-fsys=`/`-fno-sys=` flags
    // (`lib/compiler/build_runner.zig:169-174`) and is never an entry in the
    // `-D` map, so forwarding `-Dsystem` would set the nested graph's *default*
    // and leave the answer to that graph's own runner instead of this build's.
    // Both spellings go, so the dependency's own
    // `systemIntegrationOption(lib_name, ...)` resolves the answer this build
    // already reached: a dependency shares its parent's `Graph`
    // (`lib/std/Build.zig:352`) and `system_library_options` is a field of it
    // (`:116`, read at `:2731`).
    run.addArg(if (library == .system) b.fmt("-fsys={s}", .{lib_name}) else b.fmt("-fno-sys={s}", .{lib_name}));
    // Forward the selected executor and its dynamic-linker support.
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });
    // The nested build carries this workspace's job count and summary in its own
    // command line. Nothing can append a `-j` to a `Run` step's command, so a
    // nested build left to derive its own width takes `cpu_count - 1`
    // (`std/Io/Threaded.zig:1639`) instead, and the consumer this step proves
    // then compiles at a different width from the build that asked for it -
    // and at a different width again on whichever machine runs the gate.
    // `--summary all` is for the same reader: the nested build is a separate
    // graph whose steps are named after the consumer package, and a failure
    // inside it is otherwise one unnamed line.
    run.addArg("-j8");
    run.addArg("--summary");
    run.addArg("all");
    // A null `path` means "the current directory", and the working directory is
    // already the consumer package, so the default is right.
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    // The global cache is inherited whole rather than subdirectoryed: it is one
    // shared store of packages and hashes, so a nested build left to resolve its
    // own would fetch again what this one already holds, and would write
    // outside the root this workspace approved. Two tokens, as documented at
    // `lib/compiler/build_runner.zig:1675`, which is also how the compiler emits
    // it from a build script of its own
    // (`lib/std/Build/Step/Compile.zig:1478-1479`).
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArg("--global-cache-dir");
        run.addArg(global_cache);
    }
    // The install prefix this invocation resolved, handed on when the caller
    // named one. A nested `zig build` left to resolve its own installs into
    // `consumer/zig-out` - a build artefact inside a source package - rather
    // than into the directory the caller asked for. A relative `--prefix`
    // would resolve against the working directory set above, `consumer/`, and
    // not against this build's root, so it is made absolute before it is
    // handed on. `DESTDIR` needs no forwarding, because the nested build
    // inherits the environment this one ran with.
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    // The caller's own arguments, last and behind `--`: `--` is where the build
    // runner stops parsing options and keeps the rest as `b.args`
    // (`lib/compiler/build_runner.zig:428-430`), so this `--` has to follow
    // every argument above - those are this package's own bookkeeping with the
    // nested build, and only what the caller typed after `--` belongs to the
    // program. `consumer/src/main.zig` documents `--provider <path>` as a
    // command-line input, and this is the only place those words can enter the
    // nested graph at all. `consumer/build.zig` forwards its own `b.args`
    // to the run step, so what lands here reaches `src/main.zig` on the second
    // hop unchanged.
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    // The nested build is the step's only observable effect.
    run.has_side_effects = true;
    return run;
}

/// True when this build can execute `target`'s binaries.
///
/// `std.zig.system.getExternalExecutor` (`lib/std/zig/system.zig:42`) is the
/// predicate `std.Build.Step.Run` applies to the artifact it is about to spawn
/// (`lib/std/Build/Step/Run.zig:1268`), and `allow_*` carries this build's own
/// executor switches, so the two cannot disagree. `link_libc` holds in every
/// mode this package builds; the `.qemu` arm carries `Run`'s own second gate.
fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = &b.graph.host.result;
    const candidate = &target.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = b.enable_darling,
        .allow_qemu = b.enable_qemu,
        .allow_wasmtime = b.enable_wasmtime,
        .allow_wine = b.enable_wine,
        // `consumer/` builds its executable with `b.addExecutable` and no
        // linkage, so `Run`'s musl half of `need_cross_libc` never holds here.
        .qemu_fixes_dl = candidate.isGnuLibC() and b.libc_runtimes_dir != null,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(b.graph.io, host, candidate, options)) {
        .native, .rosetta => true,
        // Reachable only for an executor the switches above enabled, each of
        // which `Run` gates on the same switch and nothing else.
        .wine, .wasmtime, .darling => true,
        // Not a yes on its own: `Run` fails a cross GNU libc target given no
        // `--libc-runtimes`, so this step installs it instead. Every other QEMU
        // case still runs.
        .qemu => !(candidate.isGnuLibC() and b.libc_runtimes_dir == null),
        // Same OS and CPU with no dynamic linker to load, or an architecture
        // and system this build has no enabled executor for.
        .bad_dl, .bad_os_or_cpu => false,
    };
}

/// Writes `lib/pkgconfig/sqlite3.pc` and installs it.
///
/// This is the one file that is *nearly* upstream's. `upstream/sqlite3.pc.in`
/// is the template upstream's own install uses, and every field below is
/// upstream's field with its value resolved:
///
///   * `Name: SQLite` and `Description: SQL database engine` are
///     `upstream/sqlite3.pc.in:11-12` verbatim.
///   * `Version` is this build's release, checked against `src/sqlite3.h:149`.
///   * `prefix` is `${pcfiledir}/../..` rather than a substituted absolute path.
///     Upstream's template writes `@prefix@` (`upstream/sqlite3.pc.in:3`) because
///     its configure step knows the prefix; this graph does not know where
///     `--prefix` will point when it writes the file, and pkg-config resolves
///     `${pcfiledir}` against the `.pc` it found, so the installed file is correct
///     wherever the prefix landed - including a Nix store path that is only known
///     at build time.
///   * `Libs` is `-L"${libdir}" -lsqlite3`, exactly `upstream/sqlite3.pc.in:14`.
///     The name does not change with linkage: a C consumer asks for
///     `-lsqlite3` and the linker resolves it to `libsqlite3.a` or, through the
///     `libsqlite3.so` symlink, to the shared object.
///   * `Libs.private` is `upstream/sqlite3.pc.in:15`'s list with the two values
///     this configuration does not have removed. A static consumer needs the
///     rest to link; a shared consumer already has them inside the object.
///   * `Cflags` is `-I"${includedir}"`, upstream's `upstream/sqlite3.pc.in:16`.
///     Nothing is added to it: `SQLITE_API` is empty by default
///     (`src/sqlite3.h:72-74`), so a consumer of this build's shared object needs
///     no `dllimport` decoration to use the same header.
fn add_pkg_config(b: *std.Build, platform: Platform, linkage: std.builtin.LinkMode) void {
    const files = b.addWriteFiles();
    // The returned step is bound to the install step. `addInstallFileWithDir`
    // *creates* a `Step.InstallFile` and nothing more - dropping the return
    // value builds nothing and installs nothing, and the omission is silent:
    // the step exists, it is simply never in the graph, so an install that was
    // missing its `.pc` file would still report success.
    const install_pc = b.addInstallFileWithDir(
        files.add("sqlite3.pc", b.fmt(
            \\# sqlite3.pc for the SQLite {f} SDK.
            \\#
            \\# Generated from upstream/sqlite3.pc.in, which is upstream's own template:
            \\# Name and Description are its lines 11-12, Libs its line 14, and
            \\# Libs.private its line 15 with the two entries this configuration does
            \\# not need removed - @LDFLAGS_ZLIB@, because sqlite3.c reaches zlib only
            \\# behind SQLITE_ENABLE_FTS5 which this build does not define, and
            \\# @LDFLAGS_ICU@, likewise. `prefix` is pcfiledir-relative so the
            \\# installed file is correct wherever --prefix put it.
            \\prefix=${{pcfiledir}}/../..
            \\exec_prefix=${{prefix}}
            \\libdir=${{prefix}}/lib
            \\includedir=${{prefix}}/include
            \\
            \\Name: SQLite
            \\Description: SQL database engine
            \\Version: {f}
            \\
            \\Requires:
            \\Libs: -L"${{libdir}}" -lsqlite3
            \\Libs.private:{s}{s}{s}
            \\Cflags: -I"${{includedir}}"
            \\
        , .{
            upstream_version,
            upstream_version,
            if (platform.separate_m) " -lm" else "",
            if (platform.separate_dl) " -ldl" else "",
            if (platform.separate_pthread) " -lpthread" else "",
        })),
        .prefix,
        "lib/pkgconfig/sqlite3.pc",
    );
    b.getInstallStep().dependOn(&install_pc.step);
    _ = linkage;
}

/// Installs the carried licence text and provenance records under
/// `share/licenses/sqlite/`.
///
/// A private repository removes no upstream obligation. SQLite's grant is a
/// public-domain dedication, and upstream writes it in two places in this tree:
/// the blessing at the head of every source file (`src/sqlite3.h:1-8`) and
/// `upstream/LICENSE.md`. Both install. `FORK-LICENSE.md` records the
/// owner-authorised grant for this fork's own files; `UPSTREAM.md` and
/// `UPSTREAM.sha256` record the pin; the rest are this fork's records.
fn install_licence_records(b: *std.Build) void {
    for (licence_records) |record| {
        // Bound, for the reason `add_pkg_config` says.
        const install_record = b.addInstallFileWithDir(
            b.path(record),
            .prefix,
            b.fmt("share/licenses/sqlite/{s}", .{std.fs.path.basename(record)}),
        );
        b.getInstallStep().dependOn(&install_record.step);
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const system_default = b.option(
        bool,
        "system",
        "Link an installed libsqlite3 instead of compiling src/, and translate the " ++
            "installed headers instead of the bundled ones. This supplies the " ++
            "default of systemIntegrationOption(\"sqlite3\"); a build runner that " ++
            "decides the mode itself (-fsys=sqlite3) overrides it. Not gated in " ++
            "this wave: see build.zig's module comment on system mode.",
    ) orelse false;

    const use_system = b.systemIntegrationOption(lib_name, .{ .default = system_default });
    const library: Library = if (use_system) .system else .bundled;

    const linkage_option = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Deliver the native library as a static archive (the default) or as a real " ++
            "shared object with upstream's libsqlite3.so.0 ABI name. This selects " ++
            "the delivery and never the dispatch: the same amalgamated translation " ++
            "unit is compiled either way. In system mode this graph builds no " ++
            "artifact at all, so there the option names the kind of installed " ++
            "library to bind to instead, and it defaults to dynamic.",
    );

    // Two defaults, because the two modes had two. The bundled graph compiled a
    // static archive before this option existed and must keep doing so.
    // `linkSystemLibrary`'s own default is `.dynamic`
    // (`lib/std/Build/Module.zig:363`), and system mode must keep that too.
    // Deriving one from the other would silently change a consumer's linkage in
    // the mode that option was not written for.
    const linkage: std.builtin.LinkMode = linkage_option orelse
        (if (library == .system) .dynamic else .static);

    // `-Druntime` selects the *dispatch*, and it is orthogonal to `-Dlinkage`:
    // the option says which artifact this build delivers and installs, this one
    // says whether the Zig facade calls it through a link line or through a
    // table an explicit `load` fills. Under `-Druntime` nothing is linked into
    // the facade module at all, so a caller may name a provider this tree did
    // not build - and the artifact is still built and installed, so a caller may
    // equally name the one it did.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve the native entry points at run time instead of linking them. " ++
            "The facade keeps the same translated headers and the same public " ++
            "types; each selected native function becomes a dispatch through " ++
            "one process-lifetime table that an explicit load(source) fills, " ++
            "and the module links no archive. Independent of -Dlinkage, which " ++
            "still decides which artifact this build delivers and installs. " ++
            "Default off, and a linked build is unchanged in every respect.",
    ) orelse false;

    // `build.zig.zon .version` and the version this build stamps into
    // `sqlite3.pc`, names into the shared object's file name and documents in
    // four other places are one fact. `std.SemanticVersion.parse` fails loudly
    // rather than wrapping a non-version, and the comparison catches a manifest
    // edited without the source it describes.
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the version read out " ++
            "of src/sqlite3.h; see UPSTREAM.md");
    }

    const published = addGraph(b, target, optimize, library, linkage, runtime_loaded, true);

    // In system mode there is no artifact from this tree to install and no
    // program to build, and installing an empty stand-in would be a claim this
    // build cannot make.
    if (published.c_lib) |c_lib| {
        b.installArtifact(c_lib);
        add_pkg_config(b, published.platform, deliveredLinkage(target, linkage));
        install_licence_records(b);

        const shell_exe = add_program(
            b,
            target,
            optimize,
            linkage,
            published.platform,
            c_lib,
            shell,
            programName(b, target, shell.name, true),
        );
        b.installArtifact(shell_exe);
        addOracle(b);
    }

    // `zig build` also compiles the example. The example is the cheapest thing
    // that proves the facade, the translated headers and the C archive agree on
    // types, symbols and link-time dependencies. It is compiled, not installed:
    // it is a proof, not a deliverable.
    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, published.module);
    const example = b.addExecutable(.{
        .name = "sqlite3-smoke",
        .root_module = example_mod,
    });
    b.getInstallStep().dependOn(&example.step);

    // A run artifact already depends on building the executable, which depends
    // on compiling the C and linking the facade. `zig build smoke` deliberately
    // does not depend on the install step: installing is `zig build`'s job and
    // conflating the two would make a smoke run depend on the install layout.
    const run_example = b.addRunArtifact(example);
    run_example.has_side_effects = true;
    if (b.args) |args| run_example.addArgs(args);
    b.step("smoke", "Run the deterministic example program").dependOn(&run_example.step);

    // The test root is `tests.zig`, which names the test blocks; a root that
    // only re-exported them would discover no tests and still exit zero.
    // `addRunArtifact` is used rather than a plain compile so that this is a
    // real runnable test step for whatever `-Dtarget` names: a foreign target is
    // left to whichever executor the cross-test harness detects, and this build
    // does not decide that.
    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, published.module);
    const unit_tests = b.addTest(.{
        .name = "sqlite3-tests",
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.has_side_effects = true;
    b.step("test", "Run the behavioural tests").dependOn(&run_tests.step);

    // The separate consumer package, built as its own `zig build`. It runs when
    // this host can execute the selected target and installs when it cannot,
    // which is `hostCanExecute` rather than a query predicate: a cross-compiled
    // consumer binary cannot run here, and a native one can run under an enabled
    // executor. An install is compile evidence and nothing more.
    //
    // `library` is the mode `build` resolved, not the option a caller typed, so
    // the nested build is asked for the configuration this build is actually
    // in.
    b.step("consumer", "Build or run the consumer/ package for the selected target")
        .dependOn(&runConsumer(b, target, optimize, library, deliveredLinkage(target, linkage), runtime_loaded).step);

    // The cross target gate. Compiling the tests, the example, the shell and the
    // whole amalgamated closure for each target is what makes this a check of
    // the facade rather than of an unreferenced archive. Nothing runs here, and
    // no target is dropped - see "No target is refused" in the module comment.
    const check_step = b.step(
        "check",
        "Compile the native library, the facade, the tests, the example and " ++
            "the sqlite3 shell for all six check targets without running any of them",
    );
    if (!target.query.isNative()) {
        add_target_check(b, check_step, target.query, optimize, library, linkage, runtime_loaded);
    } else {
        // One matrix, whatever the delivery. `-Dlinkage=dynamic` used to walk a
        // shorter list that dropped every target whose OS has no dynamic
        // linker. A caller who names such a target by hand is refused by
        // `deliveredLinkage` instead, and `check` is not the step that refuses.
        //
        // `[0..]`, not `.*`: `.*` is for dereferencing a single optional or
        // error-union payload, so the pointer-to-array has to become a slice
        // before it can be iterated.
        for (check_targets[0..]) |query| {
            add_target_check(b, check_step, query, optimize, library, linkage, runtime_loaded);
        }
    }

    // Which platform configuration this graph compiled, and which artifact it
    // hands back, are facts worth reading out of the build rather than
    // inferring from a cache directory. These are configure-time lines, not
    // gate results: nothing has been compiled when they print.
    if (published.c_lib != null) {
        std.debug.print(
            "sqlite: 1 amalgamated translation unit, no SQLITE_* compile option defined, {s}\n",
            .{published.platform.kind()},
        );
        std.debug.print("sqlite: {s}\n", .{switch (deliveredLinkage(target, linkage)) {
            .static => "static archive libsqlite3.a (default)",
            .dynamic => b.fmt("shared object libsqlite3.so.{d}.{d}.{d}, soname libsqlite3.so.{d}", .{
                abi_version.major,
                abi_version.minor,
                abi_version.patch,
                abi_version.major,
            }),
        }});
        if (runtime_loaded) {
            // Dispatch is a separate fact from delivery, and a runtime-loaded
            // build links nothing into the facade module: the caller names a
            // provider with an explicit `load(source)` and the symbols arrive
            // through the platform loader. Printing it here is what keeps "the
            // library is still built and installed" from reading as "the module
            // links it".
            std.debug.print(
                "sqlite: runtime-loaded dispatch (-Druntime=true); the facade module " ++
                    "links no archive and a provider is named by an explicit " ++
                    "load(source)\n",
                .{},
            );
        }
    } else {
        std.debug.print("sqlite: system libsqlite3 (-lsqlite3) and the installed headers; this package installs nothing and builds no shell\n", .{});
        if (runtime_loaded) {
            std.debug.print(
                "sqlite: runtime-loaded dispatch (-Druntime=true) over the installed " ++
                    "provider named by an explicit load(source)\n",
                .{},
            );
        }
    }
}

/// Attaches the upstream-interop gate.
///
/// This is the upstream-interop half of the fixture policy, and it is a
/// *different* proof from the hand-computed known answers `tests.zig` checks.
/// What it proves is that `tools/fixture/aggregate.sql` is answered identically
/// by this package's facade and by upstream's own `src/shell.c` driving the same
/// library: two independent front ends, one SQL text, one expected table. A
/// facade that mis-decoded an integer, truncated a text value or reordered a
/// column would disagree with the shell here.
///
/// `tools/fixture/expected.tsv` is a fixture, not a captured output: it is the
/// table `NOTICE.md` and `README.zig.md` describe, hand-computed from the twelve
/// seeded rows and written before any gate was run.
///
/// The work is in `tools/check-oracle.sh` rather than in build steps, for two
/// reasons. A comparison needs somewhere to put the shell's stdout, and a
/// `Run` step's captured output is not a file `diff` can be pointed at without
/// the extra plumbing that script *is*; and the script has to be runnable on its
/// own - against an installed prefix, after a distribution's own build, or by
/// hand - which a build step is not. `zig build oracle` therefore installs and
/// then runs the script with the installed binary's path, and CI and the driver
/// run the same script.
///
/// It installs first rather than running the build-cache copy, because in a
/// dynamic build the shell needs `libsqlite3.so.0` beside it in `lib/` and only
/// the installed layout has that arrangement (`installedRPath`).
fn addOracle(b: *std.Build) void {
    const oracle = b.step(
        "oracle",
        "Run upstream's sqlite3 shell over tools/fixture/aggregate.sql and " ++
            "compare its output with tools/fixture/expected.tsv",
    );
    oracle.dependOn(b.getInstallStep());
    const run = b.addSystemCommand(&.{"bash"});
    run.setName("sqlite3 fixture oracle");
    run.addFileArg(b.path("tools/check-oracle.sh"));
    run.addArg(b.getInstallPath(.bin, shell.name));
    // The shell writes a temporary file, so this step is never served from a
    // cache and its result is the script's exit code.
    run.has_side_effects = true;
    oracle.dependOn(&run.step);
}

/// Whether this target's OS has a dynamic linker at all, and therefore whether
/// it can carry a shared object.
///
/// Windows uses its PE/COFF loader without an interpreter path. Other shared
/// targets need a dynamic linker. WASI has neither, which is the one refusal
/// this graph makes.
fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// The linkage this build delivers, or a refusal when the target cannot carry
/// what was asked for.
///
/// There is no substitution here, deliberately. Handing back an archive under a
/// shared object's name would be a result the caller did not request and cannot
/// tell from support, so a shared request on a target whose OS has no dynamic
/// linker stops here, with a message that names the target, the reason and the
/// way out.
///
/// `add_c_library`, `addGraph`, `add_program` and `build` all resolve through
/// this one function, so the artifact, the declarations it is paired with and
/// the installed `sqlite3.pc` cannot describe different linkages.
fn deliveredLinkage(
    target: std.Build.ResolvedTarget,
    requested: std.builtin.LinkMode,
) std.builtin.LinkMode {
    if (requested == .static) return .static;
    if (targetHasDynamicLinker(target)) return .dynamic;

    const os_tag = target.result.os.tag;
    // This is a free function, so there is no `Build` here to format through.
    const message = std.fmt.allocPrint(std.heap.page_allocator,
        \\zig build: -Dlinkage=dynamic was asked for {s}, whose operating system has
        \\no dynamic linker, so no shared object can be built or loaded there.
        \\std.Target.DynamicLinker.kind reports `{s}` for it, which is what this
        \\build uses to decide.
        \\
        \\Nothing is substituted: an archive installed under a shared object's name
        \\is a result the caller did not ask for. Use -Dlinkage=static for this
        \\target; the compiled C is identical either way.
        \\
    , .{ @tagName(os_tag), @tagName(std.Target.DynamicLinker.kind(os_tag)) }) catch
        "zig build: -Dlinkage=dynamic was asked for a target with no dynamic linker.";
    @panic(message);
}