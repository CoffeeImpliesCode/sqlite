# sqlite3

SQLite 3.53.4 — the SQL database engine — as a complete standalone Zig SDK: the
amalgamated library, upstream's own `sqlite3` command-line shell, the two public
headers, a typed Zig surface, the raw translated C route and an optional
runtime-loading route, built with no configure script, no make, no autosetup and
no build-time download.

* Upstream: the `sqlite-amalgamation-3530400.zip` and `sqlite-src-3530400.zip`
  release artefacts, SQLite 3.53.4 of 2026-07-24, Fossil check-in
  `bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc` — see
  [`UPSTREAM.md`](UPSTREAM.md).
* Native source: unmodified. All 1299 upstream files are recorded by digest in
  [`UPSTREAM.sha256`](UPSTREAM.sha256).
* Licence: **public domain**, by dedication — that is upstream's term and this
  fork's own files share it — see [`NOTICE.md`](NOTICE.md) and
  [`FORK-LICENSE.md`](FORK-LICENSE.md).
* Upstream's own README is preserved verbatim in
  [`README.upstream.md`](README.upstream.md) and in `upstream/README.md`, and is
  reproduced at the end of this file.
* **No gate has been run from this tree.** Every result below is marked
  `PENDING-VERIFICATION`. The driver owns every build, test, smoke run and
  cross-target check, and this document does not report one it did not observe.

## Native-source deviations

**None.** Every file under `src/`, `upstream/` and `test/` is byte-identical to
the two release archives. No portability patch, no reformat, no `#if` added
around a platform workaround.

That is a checkable claim rather than an assertion:

```sh
sha256sum -c UPSTREAM.sha256          # the bytes, all 1299 files
tools/check-provenance.sh             # the bytes, the file set, the check-in, the licence
```

`tools/check-provenance.sh` also rejects a file that appears under `src/`,
`upstream/` or `test/` without a recorded digest, which a checksum run alone
cannot see. Any future native edit has to move those digests, add a per-file
record to `NOTICE.md` and a numbered entry to [`CHANGELOG.md`](CHANGELOG.md) in
the same change, and needs an observed failure to justify it.

Three upstream facts that shape this SDK, all read out of the source rather than
assumed:

* **The release is a check-in, not a patched tree.** `src/sqlite3.c:20-21` says
  the content "comes from Fossil check-in bf7c7f30031888f4e796e429ab3978879485
  with changes in files:" and then lists **no files**. `src/sqlite3.h:151`'s
  `SQLITE_SOURCE_ID` names the full 64-character check-in, and
  `upstream/manifest` hashes — by upstream's own documented method, see
  `UPSTREAM.md` — to exactly that name.
* **The amalgamation is upstream's own generator output, shipped checked in.**
  `upstream/README.md` names `tool/mksqlite3c.tcl` as its producer and calls the
  amalgamation "the recommended way of using SQLite in a larger application".
  `src/sqlite3.c:11-18` is upstream's own statement that this file is all you
  need to compile SQLite. It is not a stand-in for the generator; it *is* what
* **The upstream test suite ships and this package does not run it.** `test/` is
  vendored whole — 1285 files, 87 774 656 bytes: the TCL scripts under
  `test/*.test` and `test/*.tcl`, 32 C support programs (the fuzzers, the thread
  and stress drivers, `test/kvtest.c`, `test/testloadext.c` and their
  companions), and the generated `fuzzdata*.db` inputs. Nothing is dropped and
  nothing is edited.

  It still cannot be built here, and the reason is structural rather than a
  matter of tolerance. `upstream/main.mk:1799` builds `testfixture` from
  `TESTFIXTURE_SRC`, which `:1794-1796` defines as `$(TESTSRC) tclsqlite-ex.c`
  plus `sqlite3.c`, and `$(TESTSRC)` (`:722`) is a list of `src/test1.c` …
  `src/test6.c` and the rest of the canonical `src/` tree. **None of those C
  files is in this tree**: `src/` holds only the four amalgamation files, and
  `upstream/` holds only the ten release-metadata files. TCL 8.6 development
  libraries are the second requirement
  (`upstream/README.md`: "many makefile targets require a 'tclsh' TCL
  interpreter version 8.6 or later"), and `autosetup` plus `make` are the third.
  So `build.zig` has no `upstream-test` step and fetches nothing to stand in for
  one. What it has instead is named below and in `README.zig.md`.

One upstream fact is recorded as an **open question rather than resolved**:
869 of the 1285 files under `test/` match the SHA3-256 upstream's own Fossil
manifest records for them and 416 do not, and the cause is not established. The
`test/` tree is unedited, uncompiled and unrun here, so nothing this package
builds is affected; `UPSTREAM.md` and `FORK-NOTES.md` carry the detail.

## Native-build deviations

What the compiled package does that upstream's autosetup-and-make build does not.
Each is a fork decision with a stated reason; none changes an algorithm.

* **Zig builds it; upstream's build system is unused.** `build.zig` compiles the
  same two translation units upstream's own `upstream/main.mk:2094` names for the
  amalgamation — `sqlite3.c` (269 649 lines) and, for the program, `shell.c`
  (37 415 lines) — plus the two installed headers. No `configure`, no
  `autosetup`, no `tclsh`, no `jimsh`, no `make`, no CMake and no download.
* **No `SQLITE_*` macro is defined anywhere.** Not on the library line, not on the
  shell line, not on the translation line. Every configuration decision is left
  to `sqlite3.c`'s own detection, and each one that matters is a block of
  upstream source: the OS arm at `src/sqlite3.c:16538-16548`, `SQLITE_THREADSAFE`
  defaulting to 1 at `src/sqlite3.c:15106-15111`, the `__wasi__` arm at
  `src/sqlite3.c:11676-11685`, and the `sqlite_cfg.h` include at
  `src/sqlite3.c:14685` that nothing here generates a header for.

  The cost is stated rather than hidden: this is SQLite's *default*
  configuration, not the configuration most distributions ship. There is no
  `SQLITE_ENABLE_FTS5`, no `SQLITE_ENABLE_JSON1`, no
  `SQLITE_ENABLE_MATH_FUNCTIONS`, no `SQLITE_ENABLE_RTREE` and no
  `SQLITE_ENABLE_COLUMN_METADATA`. `PRAGMA compile_options` reports that at run
  time and `smoke.zig` prints it, and a consumer that needs one of them needs a
  differently configured SQLite — a build-time choice, not something a caller
  discovers at run time.
* **Three link libraries, named per target from what the C actually references.**
  Upstream's own `sqlite3.pc.in:15` lists five `@LDFLAGS_*@` substitutions; this
  build names three, and names them from source rather than from a probe it
  cannot run. `-lm`: `ceil` and `floor` are called unconditionally at
  `src/sqlite3.c:136436-136437`, and `src/shell.c:8201-8202` does the same.
  `-ldl`, where `dlopen` lives in a separate library: `src/sqlite3.c:47240` under
  `#ifndef SQLITE_OMIT_LOAD_EXTENSION` (`src/sqlite3.c:47232`). `-lpthread`, where
  `SQLITE_MUTEX_PTHREADS` selects the pthread mutex at
  `src/sqlite3.c:30623-30625`. Not named on Windows (where the mutex is
  `SQLITE_MUTEX_W32`, `src/sqlite3.c:18417-18425`, and the loader is
  `LoadLibrary`, `src/sqlite3.c:31044`) nor on WASI (upstream's own arm sets
  `SQLITE_OMIT_LOAD_EXTENSION` and `SQLITE_THREADSAFE 0`, and wasi-libc carries
  the maths in the C library with no separate `libm`). `@LDFLAGS_ZLIB@` and
  `@LDFLAGS_ICU@` are absent because nothing this configuration compiles
  references them: `grep -c 'zlib.h' src/sqlite3.c` is 0 and
  `grep -c 'unicode/ucnv.h' src/sqlite3.c` is 0.
* **Two delivery linkages.** `-Dlinkage=static` (default) produces
  `libsqlite3.a`; `-Dlinkage=dynamic` produces a real shared object with
  upstream's `libsqlite3.so.0` soname. That soname is not a guess:
  `upstream/main.mk:1516-1519` says the `libsqlite3.so.0` link exists "in an
  attempt to reduce downstream disruption when performing upgrades from pre-3.48
  to a version 3.48 or higher", and `upstream/main.mk:1554-1563` installs
  `libsqlite3.so.$(PACKAGE_VERSION)` with `libsqlite3.so` and `libsqlite3.so.0`
  links. `build.zig` therefore matches the **soname**, which is what a consumer
  binary records in `DT_NEEDED` and what has to agree with every other SQLite on
  the machine, and says so: the delivered file is `libsqlite3.so.0.53.4`, where
  upstream's own file name would be `libsqlite3.so.3.53.4`. One field cannot
  produce both, because Zig's `Compile.version` is a single triple. A C consumer
  writes `-lsqlite3`, which resolves to the unversioned name either way.
* **The full installed closure, from one writer.** `lib/libsqlite3.a` (or the
  shared object and its two links); `include/sqlite3.h` and `include/sqlite3ext.h`
  — exactly what `upstream/main.mk:1613-1614` installs; `lib/pkgconfig/sqlite3.pc`,
  the only generated file that is installed, relocatable through
  `prefix=${pcfiledir}/../..`; `bin/sqlite3`, upstream's own shell; and
  `share/licenses/sqlite/` holding `LICENSE.md` and `sqlite3.h` — upstream's two
  texts that actually carry the dedication — together with this fork's six
  records `NOTICE.md`, `FORK-LICENSE.md`, `UPSTREAM.md`, `UPSTREAM.sha256`,
  `FORK-NOTES.md` and `CHANGELOG.md`. Eight files in all, which is exactly
  `licence_records` in `build.zig:368-377`. Upstream's makefile installs the
  library, the headers and the shell; it writes no `.pc` file at all, so
  `sqlite3.pc.in` is a template with no build rule for it in `main.mk`.
* **A typed Zig surface beside the raw one.** `zig/root.zig` publishes `Db`,
  `Statement`, `Step`, `Status`, `ColumnType` and `OpenFlags` over the translated
  `c` module, with an error set cut at what its own code checked and ownership
  rules a caller must respect. Documented in [`README.zig.md`](README.zig.md).
* **A separate consumer package**, reached only through
  `b.dependency("sqlite3", …)` in its own manifest, whose program checks a
  grouped aggregation against a table hand-computed in its source.
* **An upstream-interop gate.** `tools/check-oracle.sh` runs the fixture SQL
  through upstream's own shell and compares the output byte for byte with
  `tools/fixture/expected.tsv`. Two front ends — this package's facade and
  `src/shell.c` — answering one question against one independently derived
  table. It is not a run of SQLite's TCL suite and does not claim to be.

### History of these deviations

| Change | Why | Where |
|---|---|---|
| Zig replaces autosetup and make | the amalgamation is one translation unit; nothing upstream's build does applies to it, and a configure step would pull TCL into every gate | `build.zig` |
| No `SQLITE_*` option defined | a fixed, stated configuration beats a distributed one; `PRAGMA compile_options` reports it | `build.zig`, `Platform` |
| Shared object gets `libsqlite3.so.0` | that is the ABI name upstream states, and it is the one that has to match every other SQLite on the machine | `build.zig`, `deliveredLinkage` |
| Typed facade added | a convenience over the raw route, never a replacement; every method is a few lines over a declaration in `c` | `zig/root.zig` |
| Runtime-loading route added | lets a program name a provider instead of linking one; explicit path or explicit SONAME, no fallback | `runtime/`, `-Druntime=true` |
| Oracle fixture added | the upstream TCL suite cannot run here, so a small independent interoperability check replaces it and says what it is | `tools/check-oracle.sh` |

## Build, run and test matrix

Every row below is `PENDING-VERIFICATION` except the `cross-test` row, which
carries an observed harness run and names its receipt. No other gate has been
run from this tree, this document reports none, and the driver owns all of them.

| Command | What it does | Status |
|---|---|---|
| `zig build` | install the library, both headers, `bin/sqlite3`, the relocatable `sqlite3.pc` and the licence and provenance records; compile the example | `PENDING-VERIFICATION` |
| `zig build test` | run `tests.zig` for the selected target (`-Dtarget`; the host when absent) | `PENDING-VERIFICATION` |
| `zig build test -Doptimize=ReleaseSafe` | the same, in the second mode | `PENDING-VERIFICATION` |
| `zig build smoke` | run `smoke.zig` | `PENDING-VERIFICATION` |
| `zig build oracle` | install, then run upstream's shell over `tools/fixture/aggregate.sql` and diff against `tools/fixture/expected.tsv` | `PENDING-VERIFICATION` |
| `zig build consumer` | build the separate `consumer/` package; run it when this host can execute the selected target, install it when it cannot | `PENDING-VERIFICATION` |
| `zig build check` | compile the library, facade, tests, example and shell for all six check targets, running nothing | `PENDING-VERIFICATION` |
| `tools/check-provenance.sh` | the 1299 recorded digests, the exact file set, the Fossil check-in identity, the version in three places, the public-domain grant, the preserved README and the fixture/tests SQL agreement | `PENDING-VERIFICATION` |
| `cross-test` | the published 53-platform Zig 0.16 Tier 1/2 table, via this repository's build graph and `cross-test.profile.sh` | **OBSERVED, 2026-10-05** — run `20261005-191626-52905-3050`, `--jobs 8 --build-jobs 8`, harness **exit 1**: 53 cells, 20 pass at 25/25 tests each, 15 `build_only`, **18 build failures**, 0 partial. See the matrix section below. Not 53 test passes |

### The six-target compile baseline

`zig build check` walks all six, runs nothing, and **refuses no target**. There
is no refusal list and no `refused_check_targets` here, which is the opposite of
a graph that drops a row: whether a cell builds is a fact for the gate to report,
not something this file may pre-judge.

| Target | Link libraries | What decides it |
|---|---|---|
| `x86_64-linux-gnu` | `-lm -ldl -lpthread` | upstream's own Unix detection |
| `aarch64-linux-gnu` | `-lm -ldl -lpthread` | the same source, a different target |
| `aarch64-macos-none` | `-lm` | `dlopen` and pthread are in Darwin's libc |
| `x86_64-windows-gnu` | none | `SQLITE_MUTEX_W32`; the maths are in the C runtime |
| `riscv64-linux-gnu` | `-lm -ldl -lpthread` | the same Unix arm |
| `wasm32-wasi` | none | upstream's `__wasi__` arm sets `SQLITE_OMIT_LOAD_EXTENSION` and `SQLITE_THREADSAFE 0`, and wasi-libc carries the maths |

A foreign target with no executor is `build_only` coverage: compiled, never
executed, never counted as a pass. A target that fails is recorded and diagnosed,
not dropped, sampled or remapped to a mode that would pass.

### The full 53-platform matrix

`cross-test`, run from the package root, builds and **runs** `tests.zig` for
every platform in Zig 0.16.0's published Tier 1/2 table, through this
repository's own build graph, with `cross-test.profile.sh` supplying settings
only. It is not `zig build check`, which compiles six targets and runs nothing;
the two answer different questions and neither stands in for the other. The
command and its receipts belong to the driver.

#### What that run observed

Command, run from this package root on 2026-10-05 with Zig 0.16.0:

```sh
ZIG="$ZIG" "$HOME/.local/bin/cross-test" --jobs 8 --build-jobs 8 \
  --output "$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/sqlite"
```

`--jobs 8 --build-jobs 8` overrode the profile's `CROSS_BUILD_JOBS=4`; nothing
else was narrowed, and no target list was supplied.

| Outcome | Cells | What it means |
|---|---|---|
| pass | 20 | the test binary ran and reported `25 pass (25 total)` |
| `build_only` | 15 | compiled, no executor on this host, never executed, never a pass |
| build failure | 18 | every NetBSD and OpenBSD row; `unable to find dynamic system library 'dl'` |
| refused | 0 | no cell was refused or dropped |
| runtime failure | 0 | no cell compiled and then failed its run |

Harness summary: `exit_code 1`, `counts {pass 20, fail 18, build_only 15,
partial 0}`, `target_count 53`, `target_jobs 8`, `jobs_per_build 8`,
`build_timeout_seconds 5400`, `run_timeout_seconds 1800`.

Receipt: `$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/sqlite/cross-test-summary.json`,
and one `build-<target>.log` per cell under
`…/cross/sqlite/runs/20261005-191626-52905-3050/`. In this mode the run is a
`Run` step inside `zig build test`, so a cell's executed test count is in its own
`build-<target>.log`, not in a separate run log.

The 20 executed cells are `x86_64-linux` natively and the following nineteen
under the QEMU-user executors `--list` named: `aarch64-linux`,
`aarch64_be-linux`, `arm-linux`, `armeb-linux`, `hexagon-linux`,
`loongarch64-linux`, `mips-linux`, `mipsel-linux`, `mips64-linux`,
`mips64el-linux`, `powerpc-linux`, `powerpc64-linux`, `powerpc64le-linux`,
`riscv32-linux`, `riscv64-linux`, `s390x-linux`, `thumb-linux`, `thumbeb-linux`
and `x86-linux`. Every one reports `run test sqlite3-tests 25 pass (25 total)`.

The 15 `build_only` cells are `aarch64-freebsd`, `aarch64-maccatalyst`,
`aarch64-macos`, `aarch64-windows`, `arm-freebsd`, `powerpc64-freebsd`,
`powerpc64le-freebsd`, `riscv64-freebsd`, `thumb-windows`, `wasm32-wasi`,
`x86-windows`, `x86_64-freebsd`, `x86_64-maccatalyst`, `x86_64-macos` and
`x86_64-windows`. Each compiled (`Build Summary: 5/6 steps succeeded
(1 skipped)`, the skipped step being the run) and each has no executor here:
no QEMU for its OS, no Wine, no wasmtime.

The 18 failures are the nine NetBSD rows and the nine OpenBSD rows, and all
eighteen print the same line:

```
error: unable to find dynamic system library 'dl' using strategy 'paths_first'. searched paths: none
```

The cause is named in `build.zig`, not in upstream. `Platform.forTarget`
(`build.zig:498-561`) routes every non-Windows, non-WASI, non-Darwin Unix —
"Linux, the BSDs, Solaris, illumos, AIX" — through one arm that sets
`.separate_dl = true` (`build.zig:554-561`), and that arm is what puts `-ldl`
on the compile line (`build.zig:857-859`, `build.zig:919-921`) and in the
installed `sqlite3.pc` (`build.zig:1278`). Six FreeBSD rows in the same run
compiled with the same `-ldl`, so the arm is right for FreeBSD and wrong for
NetBSD and OpenBSD, where the loader is in libc. **This run therefore exposes a
build-graph defect in this fork, not an upstream or toolchain limit**, and it
is not fixed here: `build.zig` needs a NetBSD/OpenBSD arm beside the Darwin one
at `build.zig:537-548`, and whether `-lm` and `-lpthread` are also needed on
those two operating systems is **not established**, because the build stopped
at `-ldl` and never reached them. See `FORK-NOTES.md` item 9.

## Consumption

### From Zig, typed

```zig
const sqlite = @import("sqlite3");

var db = try sqlite.Db.open(":memory:", .{ .readwrite = true, .create = true });
defer db.close();
try db.exec("CREATE TABLE ledger(entry INTEGER, account TEXT, cents INTEGER)");

var insert = try db.prepare("INSERT INTO ledger VALUES(?1, ?2, ?3)");
defer insert.finalize() catch {};
for ([_][3]i64{ .{ 1, 100, 0 }, .{ 3, 50, 0 }, .{ 6, 300, 0 } }) |_| {
    insert.reset();
    try insert.bindInt64(1, 1);
    try insert.bindInt64(2, 2);
    try insert.bindInt64(3, 3);
    try insert.runToCompletion();
}
```

The real program is `consumer/src/main.zig`; it seeds twelve rows and checks the
grouped answer against arithmetic written out in its own source. See
[`README.zig.md`](README.zig.md) for the whole surface.

### From Zig, the raw native route

`sqlite.c` is the translation of the whole public header, under upstream's own
names:

```zig
const sqlite = @import("sqlite3");

const code = sqlite.c.sqlite3_compileoption_used("SQLITE_ENABLE_FTS5"); // 0 here
```

Nothing is renamed and nothing is hidden; `README.zig.md` says what `c` carries
beyond the declarations.

### From C

The installed tree is a plain C installation: `lib/pkgconfig/sqlite3.pc`,
`include/sqlite3.h`, `include/sqlite3ext.h`, and the library.

```sh
cc consumer.c $(pkg-config --cflags --libs sqlite3) -o consumer
```

`pkg-config --libs` yields `-L<libdir> -lsqlite3`, exactly
`upstream/sqlite3.pc.in:14`. A static C consumer also needs
`pkg-config --static --libs`, whose `Libs.private` this build fills with the
three libraries the configuration actually needs and omits the two it does not
(`upstream/sqlite3.pc.in:15`).

### With Nix

`package.nix` is the one source-only derivation, shared by `flake.nix` and
`devenv.nix` so the two entry points cannot describe different packages:

```sh
nix build .#static     # libsqlite3.a, the headers, sqlite3.pc, bin/sqlite3
nix build .#shared     # the same with libsqlite3.so.0.53.4
devenv shell            # canonical development environment
devenv task sdk:build   # a build with output outside this checkout
```

Lock files belong to the driver; `devenv.yaml` pins its nixpkgs revision in
source, so there is no `devenv.lock` to write, and `flake.lock` is not in this
tree.

### Runtime loading

Built with `-Druntime=true`. The native entry points resolve at run time instead
of being linked, and a program names its provider before the first call:

```sh
zig build -Dlinkage=dynamic
zig build run -Druntime=true -- --provider "$PWD/zig-out/lib/libsqlite3.so"
```

or `SQLITE_TEST_PROVIDER` in the environment. There is no default, no search and
no fallback: an absolute path is loaded or refused, a SONAME is handed to the
platform loader or refused, and a provider that does not export the whole
default-build symbol set is rejected rather than half used. `runtime/library.zig`
is the descriptor and the ABI statement; `README.zig.md` has the details.

## Licence

Public domain, by dedication — for SQLite and for this fork's own files alike.
Upstream's term is written in prose in `upstream/LICENSE.md` and as a per-file
blessing at the head of every source file (`src/sqlite3.h:1-8`,
`src/sqlite3ext.h:1-8`, and 144 times inside `src/sqlite3.c`). This fork's
material carries the same dedication under
[`FORK-LICENSE.md`](FORK-LICENSE.md). The inventory, including the one place
where upstream's own files are not covered by a single label, is
[`NOTICE.md`](NOTICE.md).

## Upstream README, verbatim

Upstream's own `README.md` is preserved at `upstream/README.md` and copied to
[`README.upstream.md`](README.upstream.md); the two are byte-identical and
`tools/check-provenance.sh` fails if they ever differ. It is reproduced here
because it is upstream's release note and **not** this package's documentation —
it describes building SQLite with `./configure && make`, TCL and the Fossil
timeline, none of which is how this package builds. Read it as upstream's own
account; read the rest of this file for the fork's.

<h1 align="center">SQLite Source Repository</h1>

This repository contains the complete source code for the
[SQLite database engine](https://sqlite.org/) going back
to 2000-05-29.  The tree includes many tests and some
documentation, though additional tests and most documentation
are managed separately.

See the [on-line documentation](https://sqlite.org/) for more information
about what SQLite is and how it works from a user's perspective.  This
README file is about the source code that goes into building SQLite,
not about how SQLite is used.

## Version Control

SQLite sources are managed using
[Fossil](https://fossil-scm.org/), a distributed version control system
that was specifically designed and written to support SQLite development.
The [Fossil repository](https://sqlite.org/src/timeline) contains the urtext.

If you are reading this on GitHub or some other Git repository or service,
then you are looking at a mirror.  The names of check-ins and
other artifacts in a Git mirror are different from the official
names for those objects.  The official names for check-ins are
found in a footer on the check-in comment for authorized mirrors.
The official check-in name can also be seen in the `manifest.uuid` file
in the root of the tree.  Always use the official name, not  the
Git-name, when communicating about an SQLite check-in.

If you pulled your SQLite source code from a secondary source and want to
verify its integrity, there are hints on how to do that in the
[Verifying Code Authenticity](#vauth) section below.

## Contacting The SQLite Developers

The preferred way to ask questions or make comments about SQLite or to
report bugs against SQLite is to visit the 
[SQLite Forum](https://sqlite.org/forum) at <https://sqlite.org/forum/>.
Anonymous postings are permitted.

If you think you have found a bug that has security implications and
you do not want to report it on the public forum, you can send a private
email to drh at sqlite dot org.

## Public Domain

The SQLite source code is in the public domain.  See
<https://sqlite.org/copyright.html> for details. 

Because SQLite is in the public domain, we do not normally accept pull
requests, because if we did take a pull request, the changes in that
pull request might carry a copyright and the SQLite source code would
then no longer be fully in the public domain.

## Obtaining The SQLite Source Code

Source code tarballs or ZIP archives are available at:

  *  [Latest trunk check-in](https://sqlite.org/src/rchvdwnld/trunk).

  *  [Latest release](https://sqlite.org/src/rchvdwnld/release)

  *  For other check-ins, browse the
     [project timeline](https://sqlite.org/src/timeline?y=ci) and
     click on the check-in hash of the check-in you want to download.
     On the resulting "info" page, click one of the options to the
     right of the "**Downloads:**" label in the "**Overview**" section
     near the top.

To access sources directly using [Fossil](https://fossil-scm.org/home),
first install Fossil version 2.0 or later.
Source tarballs and precompiled binaries for Fossil are available at
<https://fossil-scm.org/home/uv/download.html>.  Fossil is
a stand-alone program.  To install, simply download or build the single
executable file and put that file someplace on your $PATH or %PATH%.
Then run commands like this:

        mkdir -p ~/sqlite
        cd ~/sqlite
        fossil open https://sqlite.org/src

The initial "fossil open" command will take two or three minutes.  Afterwards,
you can do fast, bandwidth-efficient updates to the whatever versions
of SQLite you like.  Some examples:

        fossil update trunk             ;# latest trunk check-in
        fossil update release           ;# latest official release
        fossil update trunk:2024-01-01  ;# First trunk check-in after 2024-01-01
        fossil update version-3.39.0    ;# Version 3.39.0

Or type "fossil ui" to get a web-based user interface.

## Compiling for Unix-like systems

First create a directory in which to place
the build products.  It is recommended, but not required, that the
build directory be separate from the source directory.  Cd into the
build directory and then from the build directory run the configure
script found at the root of the source tree.  Then run "make".
See the [compile-for-unix.md](doc/compile-for-unix.md) document for
more detail.

For example:

        apt install gcc make tcl-dev  ;#  Install the necessary build tools
        tar xzf sqlite.tar.gz         ;#  Unpack the source tree into "sqlite"
        mkdir bld                     ;#  Build happens in a sibling directory
        cd bld                        ;#  Change to the build directory
        ../sqlite/configure           ;#  Run the configure script
        make sqlite3                  ;#  The "sqlite3" command-line tool
        make sqlite3.c                ;#  The "amalgamation" source file
        make sqldiff                  ;#  The "sqldiff" command-line tool
        #### Targets below require tcl-dev ####
        make tclextension-install     ;#  Install the SQLite TCL extension
        make devtest                  ;#  Run development tests
        make releasetest              ;#  Run full release tests
        make sqlite3_analyzer         ;#  Builds the "sqlite3_analyzer" tool

See the makefile for additional targets.  For debugging builds, the
core developers typically run "configure" with options like this:

        ../sqlite/configure --all --debug CFLAGS='-O0 -g'

For release builds, the core developers usually do:

        ../sqlite/configure --all

Core deliverables (sqlite3.c, sqlite3) can be built without a TCL, but
many makefile targets require a "tclsh" TCL interpreter version 8.6
or later.  The "tclextension-install" target and the test targets that follow
all require TCL development libraries too.  ("apt install tcl-dev").  It is
helpful, but is not required, to install the SQLite TCL extension (the
"tclextension-install" target) prior to running tests.  The "releasetest"
target has additional requirements, such as "valgrind".

On "make" command-lines, one can add "OPTIONS=..." to specify additional
compile-time options over and above those set by ./configure.  For example,
to compile with the SQLITE_OMIT_DEPRECATED compile-time option, one could say:

        ./configure --all
        make OPTIONS=-DSQLITE_OMIT_DEPRECATED sqlite3

The configure script uses [autosetup](https://msteveb.github.io/autosetup/).
If the configure script does not work out for you, there is a generic
makefile named "Makefile.linux-gcc" in the top directory of the source tree
that you can copy and edit to suit your needs.  Comments on the generic
makefile show what changes are needed.

## Compiling for Windows Using MSVC

On Windows, everything can be compiled with MSVC.
You will also need a working installation of TCL if you want to run tests,
though TCL is not required if you just want to build SQLite itself.
See the [compile-for-windows.md](doc/compile-for-windows.md) document for
additional information about how to install MSVC and TCL and configure your
build environment.

If you want to run tests, you need to let SQLite know the location of your
TCL library, using a command like this:

        set TCLDIR=c:\Tcl

SQLite itself does not contain any TCL code, but it does use TCL to run
tests. You may need to install TCL development libraries in order to
successfully complete some makefile targets. It is helpful, but is not
required, to install the SQLite TCL extension (the "tclextension-install"
target) prior to running tests.

The source tree contains a "make.bat" file that allows the same "make"
commands of Unix to work on Windows.  In the following, you can substitute
"nmake /f Makefile.msc" in place of "make", if you prefer to avoid this BAT
file:

        make sqlite3.exe
        make sqlite3.c
        make sqldiff.exe
        #### Targets below require TCL development libraries ####
        make tclextension-install
        make devtest
        make releasetest
        make sqlite3_analyzer.exe
 
There are many other makefile targets.  See comments in Makefile.msc for
details.

As with the unix Makefile, the OPTIONS=... argument can be passed on the nmake
command-line to enable new compile-time options.  For example:

        make OPTIONS=-DSQLITE_OMIT_DEPRECATED sqlite3.exe

## Source Tree Map

  *  **src/** - This directory contains the primary source code for the
     SQLite core.  For historical reasons, C-code used for testing is
     also found here.  Source files intended for testing begin with "`test`".
     The `tclsqlite3.c` and `tclsqlite3.h` files are the TCL interface
     for SQLite and are also not part of the core.

  *  **test/** - This directory and its subdirectories contains code used
     for testing.  Files that end in "`.test`" are TCL scripts that run
     tests using an augmented TCL interpreter named "testfixture".  Use
     a command like "`make testfixture`" to build that
     augmented TCL interpreter, then run individual tests using commands like
     "`testfixture test/main.test`".  This test/ subdirectory also contains
     additional C code modules and scripts for other kinds of testing.

  *  **tool/** - This directory contains programs and scripts used to
     build some of the machine-generated code that goes into the SQLite
     core, as well as to build and run tests and perform diagnostics.
     The source code to [the Lemon parser generator](./doc/lemon.html) is
     found here.  There are also TCL scripts used to build and/or transform
     source code files.  For example, the tool/mksqlite3h.tcl script reads
     the src/sqlite.h.in file and uses it as a template to construct
     the deliverable "sqlite3.h" file that defines the SQLite interface.

  *  **ext/** - Various extensions to SQLite are found under this
     directory.  For example, the FTS5 subsystem is in "ext/fts5/".
     Some of these extensions (ex: FTS3/4, FTS5, RTREE) might get built
     into the SQLite amalgamation, but not all of them.  The
     "ext/misc/" subdirectory contains an assortment of one-file extensions,
     many of which are omitted from the SQLite core, but which are included
     in the [SQLite CLI](https://sqlite.org/cli.html).
     
  *  **doc/** - Some documentation files about SQLite internals are found
     here.  Note, however, that the primary documentation designed for
     application developers and users of SQLite is in a completely separate
     repository.  Note also that the primary API documentation is derived
     from specially constructed comments in the src/sqlite.h.in file.

### Generated Source Code Files

Several of the C-language source files used by SQLite are generated from
other sources rather than being typed in manually by a programmer.  This
section will summarize those automatically-generated files.  To create all
of the automatically-generated files, simply run "make target&#95;source".
The "target&#95;source" make target will create a subdirectory "tsrc/" and
fill it with all the source files needed to build SQLite, both
manually-edited files and automatically-generated files.

The SQLite interface is defined by the **sqlite3.h** header file, which is
generated from src/sqlite.h.in, ./manifest.uuid, and ./VERSION.  The
[Tcl script](https://www.tcl.tk) at tool/mksqlite3h.tcl does the conversion.
The manifest.uuid file contains the SHA3 hash of the particular check-in
and is used to generate the SQLITE\_SOURCE\_ID macro.  The VERSION file
contains the current SQLite version number.  The sqlite3.h header is really
just a copy of src/sqlite.h.in with the source-id and version number inserted
at just the right spots. Note that comment text in the sqlite3.h file is
used to generate much of the SQLite API documentation.  The Tcl scripts
used to generate that documentation are in a separate source repository.

The SQL language parser is **parse.c** which is generated from a grammar in
the src/parse.y file.  The conversion of "parse.y" into "parse.c" is done
by the [lemon](./doc/lemon.html) LALR(1) parser generator.  The source code
for lemon is at tool/lemon.c.  Lemon uses the tool/lempar.c file as a
template for generating its parser.
Lemon also generates the **parse.h** header file, at the same time it
generates parse.c.

The **opcodes.h** header file contains macros that define the numbers
corresponding to opcodes in the "VDBE" virtual machine.  The opcodes.h
file is generated by scanning the src/vdbe.c source file.  The
Tcl script at ./mkopcodeh.tcl does this scan and generates opcodes.h.
A second Tcl script, ./mkopcodec.tcl, then scans opcodes.h to generate
the **opcodes.c** source file, which contains a reverse mapping from
opcode-number to opcode-name that is used for EXPLAIN output.

The **keywordhash.h** header file contains the definition of a hash table
that maps SQL language keywords (ex: "CREATE", "SELECT", "INDEX", etc.) into
the numeric codes used by the parse.c parser.  The keywordhash.h file is
generated by a C-language program at tool mkkeywordhash.c.

The **pragma.h** header file contains various definitions used to parse
and implement the PRAGMA statements.  The header is generated by a
script **tool/mkpragmatab.tcl**. If you want to add a new PRAGMA, edit
the **tool/mkpragmatab.tcl** file to insert the information needed by the
parser for your new PRAGMA, then run the script to regenerate the
**pragma.h** header file.

### The Amalgamation

All of the individual C source code and header files (both manually-edited
and automatically-generated) can be combined into a single big source file
**sqlite3.c** called "the amalgamation".  The amalgamation is the recommended
way of using SQLite in a larger application.  Combining all individual
source code files into a single big source code file allows the C compiler
to perform more cross-procedure analysis and generate better code.  SQLite
runs about 5% faster when compiled from the amalgamation versus when compiled
from individual source files.

The amalgamation is generated from the tool/mksqlite3c.tcl Tcl script.
First, all of the individual source files must be gathered into the tsrc/
subdirectory (using the equivalent of "make target_source") then the
tool/mksqlite3c.tcl script is run to copy them all together in just the
right order while resolving internal "#include" references.

The amalgamation source file is more than 200K lines long.  Some symbolic
debuggers (most notably MSVC) are unable to deal with files longer than 64K
lines.  To work around this, a separate Tcl script, tool/split-sqlite3c.tcl,
can be run on the amalgamation to break it up into a single small C file
called **sqlite3-all.c** that does #include on about seven other files
named **sqlite3-1.c**, **sqlite3-2.c**, ..., **sqlite3-7.c**.  In this way,
all of the source code is contained within a single translation unit so
that the compiler can do extra cross-procedure optimization, but no
individual source file exceeds 32K lines in length.

## How It All Fits Together

SQLite is modular in design.
See the [architectural description](https://sqlite.org/arch.html)
for details. Other documents that are useful in
helping to understand how SQLite works include the
[file format](https://sqlite.org/fileformat2.html) description,
the [virtual machine](https://sqlite.org/opcode.html) that runs
prepared statements, the description of
[how transactions work](https://sqlite.org/atomiccommit.html), and
the [overview of the query planner](https://sqlite.org/optoverview.html).

Decades of effort have gone into optimizing SQLite, both
for small size and high performance.  And optimizations tend to result in
complex code.  So there is a lot of complexity in the current SQLite
implementation.  It will not be the easiest library in the world to hack.

### Key source code files

  *  **sqlite.h.in** - This file defines the public interface to the SQLite
     library.  Readers will need to be familiar with this interface before
     trying to understand how the library works internally.  This file is
     really a template that is transformed into the "sqlite3.h" deliverable
     using a script invoked by the makefile.

  *  **sqliteInt.h** - this header file defines many of the data objects
     used internally by SQLite.  In addition to "sqliteInt.h", some
     subsystems inside of sQLite have their own header files.  These internal
     interfaces are not for use by applications.  They can and do change
     from one release of SQLite to the next.

  *  **parse.y** - This file describes the LALR(1) grammar that SQLite uses
     to parse SQL statements, and the actions that are taken at each step
     in the parsing process.  The file is processed by the
     [Lemon Parser Generator](./doc/lemon.html) to produce the actual C code
     used for parsing.

  *  **vdbe.c** - This file implements the virtual machine that runs
     prepared statements.  There are various helper files whose names
     begin with "vdbe".  The VDBE has access to the vdbeInt.h header file
     which defines internal data objects.  The rest of SQLite interacts
     with the VDBE through an interface defined by vdbe.h.

  *  **where.c** - This file (together with its helper files named
     by "where*.c") analyzes the WHERE clause and generates
     virtual machine code to run queries efficiently.  This file is
     sometimes called the "query optimizer".  It has its own private
     header file, whereInt.h, that defines data objects used internally.

  *  **btree.c** - This file contains the implementation of the B-Tree
     storage engine used by SQLite.  The interface to the rest of the system
     is defined by "btree.h".  The "btreeInt.h" header defines objects
     used internally by btree.c and not published to the rest of the system.

  *  **pager.c** - This file contains the "pager" implementation, the
     module that implements transactions.  The "pager.h" header file
     defines the interface between pager.c and the rest of the system.

  *  **os_unix.c** and **os_win.c** - These two files implement the interface
     between SQLite and the underlying operating system using the run-time
     pluggable VFS interface.

  *  **shell.c.in** - This file is not part of the core SQLite library.  This
     is the file that, when linked against sqlite3.a, generates the
     "sqlite3.exe" command-line shell.  The "shell.c.in" file is transformed
     into "shell.c" as part of the build process.

  *  **tclsqlite.c** - This file implements the Tcl bindings for SQLite.  It
     is not part of the core SQLite library.  But as most of the tests in this
     repository are written in Tcl, the Tcl language bindings are important.

  *  **test\*.c** - Files in the src/ folder that begin with "test" go into
     building the "testfixture.exe" program.  The testfixture.exe program is
     an enhanced Tcl shell.  The testfixture.exe program runs scripts in the
     test/ folder to validate the core SQLite code.  The testfixture program
     (and some other test programs too) is built and run when you type
     "make test".

  *  **VERSION**, **manifest**, **manifest.tags**, and **manifest.uuid** -
     These files define the current SQLite version number. The "VERSION" file
     is human generated, but the "manifest", "manifest.tags", and
     "manifest.uuid" files are automatically generated by the
     [Fossil version control system](https://fossil-scm.org/).

There are many other source files.  Each has a succinct header comment that
describes its purpose and role within the larger system.

<a name="vauth"></a>
## Verifying Code Authenticity

The `manifest` file at the root directory of the source tree
contains either a SHA3-256 hash or a SHA1 hash
for every source file in the repository.
The name of the version of the entire source tree is just the
SHA3-256 hash of the `manifest` file itself, possibly with the
last line of that file omitted if the last line begins with
"`# Remove this line`".
The `manifest.uuid` file should contain the SHA3-256 hash of the
`manifest` file. If all of the above hash comparisons are correct, then
you can be confident that your source tree is authentic and unadulterated.
Details on the format for the `manifest` files are available
[on the Fossil website](https://fossil-scm.org/home/doc/trunk/www/fileformat.wiki#manifest).

The process of checking source code authenticity is automated by the 
makefile:

>   make verify-source

Using the makefile to verify source integrity is good for detecting
accidental changes to the source tree, but malicious changes could be
hidden by also modifying the makefiles.

## Contacts

The main SQLite website is [https://sqlite.org/](https://sqlite.org/)
with geographically distributed backups at
[https://www2.sqlite.org/](https://www2.sqlite.org) and
[https://www3.sqlite.org/](https://www3.sqlite.org).

Contact the SQLite developers through the
[SQLite Forum](https://sqlite.org/forum/).  In an emergency, you
can send private email to the lead developer at drh at sqlite dot org.
