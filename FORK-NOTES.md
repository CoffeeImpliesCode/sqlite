# Fork notes

What this fork decided, why, and what is still open. A note here is a
`SOURCE-CONFIRMED` statement about the tree or a `PENDING-VERIFICATION` claim
about a gate. Nothing here is a verified result: the driver owns every run.

## 1. There is no Git commit to record, and none is invented

SQLite is developed in Fossil, not Git. `upstream/README.md` warns against the
opposite directly: "If you are reading this on GitHub or some other Git
repository or service, then you are looking at a mirror… Always use the official
name, not the Git-name, when communicating about an SQLite check-in."

So the identity recorded here is Fossil's: check-in
`bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`, tag
`version-3.53.4`, branch `branch-3.53`, date `2026-07-24T19:02:57.525`. Each is
read out of a file in this tree, and `tools/check-provenance.sh` recomputes the
link between them: `upstream/manifest` hashes — by upstream's own documented
method, with the trailing `# Remove this line` comment omitted — to exactly the
name in `upstream/manifest.uuid` and in `src/sqlite3.h:151`.

The two archives' own SHA-256 values are **not** recorded, because neither archive
is in this tree to hash. That is a deliberate absence rather than a gap to be
filled by looking the value up somewhere and writing it down.

## 2. The amalgamation is a generated file, and that is not a deviation

Three of the four files under `src/` are upstream generator output:
`sqlite3.c` from `tool/mksqlite3c.tcl`, `sqlite3.h` from `src/sqlite.h.in` plus
`./manifest.uuid` plus `./VERSION` through `tool/mksqlite3h.tcl`, and `shell.c`
from `src/shell.c.in` through `tool/mkshellc.tcl` (`upstream/README.md`, "###
Generated Source Code Files" and "### The Amalgamation"). None of them has an
entry in upstream's Fossil manifest, because a manifest records checked-in files
and these are not checked in.

That is worth stating because it looks like the opposite of a fidelity problem:
this is upstream's own generator's output, shipped in upstream's own release
archive, with the check-in it came from recorded in its own first comment block.
`src/sqlite3.c:20-21` names that check-in and lists **no changed file**, so the
amalgamation in this archive is the check-in.

The one thing a reader cannot take on trust is `src/sqlite3ext.h`, which *is*
checked in and *is* in the manifest. Its SHA3-256 matches
(`1b7a0ee438bb5c2896d0609c537e917d8057b3340f6ad004d2de44f03e3d3cca`), and
`tools/check-provenance.sh` fails if it ever stops matching.

## 3. The upstream test suite ships and is not run

`test/` is 1285 files and 87 774 656 bytes, vendored whole. Nothing is dropped
for size: dropping the `fuzzdata*.db` inputs would leave a tree whose tests
cannot run, because the tests that read them are the ones that find bugs.

Nothing is run either, and the reason is stronger than "TCL would be a
dependency". `test/testrunner.tcl` drives the suite through a `testfixture`
binary, and `upstream/main.mk:1799` builds that from `TESTFIXTURE_SRC`, which
`upstream/main.mk:1794-1796` defines as `$(TESTSRC) tclsqlite-ex.c` plus
`sqlite3.c`. `$(TESTSRC)` (`upstream/main.mk:722`) is `src/test1.c`,
`src/test2.c` and the rest of the canonical `src/` tree, together with
`src/tclsqlite3.c` — and **none of those files is in this repository**. The four
files under `src/` are the amalgamation's own output and the ten under
`upstream/` are release metadata; upstream's own manifest lists 2205 files, of
which this tree carries 10.

Behind that sit two more requirements: TCL 8.6 development libraries
(`upstream/README.md` is explicit that "many makefile targets require a 'tclsh'
TCL interpreter version 8.6 or later"), and `autosetup` plus `make` to generate
the rest — `parse.c`, `opcodes.c`, `keywordhash.h`, `pragma.h`. So running the
suite means re-introducing the build system this package exists to replace.

So `build.zig` has **no `upstream-test` step**, and nothing is fetched to stand in
for one: a fetched suite would be a different source tree than the release this
package pins, with no recorded digest. What replaces it is small and says so —
`tests.zig`'s hand-computed aggregation with a second implementation, and
`zig build oracle`, which runs the *same SQL text* through upstream's own shell
and compares byte for byte with the same hand-computed table. Two front ends, one
question, one answer derived on paper. Neither is a substitute for 1285 upstream
test files and neither is described as one.

## 4. No compile option is defined, and that is a policy with a cost

The build defines no `SQLITE_*` macro anywhere. The decisions are left to
`sqlite3.c`'s own detection:

| Question | Upstream's source | Result |
|---|---|---|
| Which OS arm | `src/sqlite3.c:16538-16548` | both Windows and Unix VFS are in the one unit |
| Threading | `src/sqlite3.c:15106-15111`, `:18417-18425` | `SQLITE_THREADSAFE 1` → serialized, multi-thread-safe |
| WASI | `src/sqlite3.c:11676-11685` | `SQLITE_WASI`, `SQLITE_OMIT_LOAD_EXTENSION`, `SQLITE_THREADSAFE 0` |
| Configure header | `src/sqlite3.c:14685` | `sqlite_cfg.h` is never generated, so never included |

The cost is real and is stated in `build.zig`, `README.md` and `smoke.zig`
alike: there is no `SQLITE_ENABLE_FTS5`, no `SQLITE_ENABLE_JSON1`, no
`SQLITE_ENABLE_MATH_FUNCTIONS`, no `SQLITE_ENABLE_RTREE` and no
`SQLITE_ENABLE_COLUMN_METADATA`. A fixed configuration that says what it is beats
a distributed one that says nothing; a caller who needs a feature needs a
differently configured SQLite, and that is a build-time decision belonging to
whoever makes it.

## 5. Three link libraries, and why `@LDFLAGS_ZLIB@` and `@LDFLAGS_ICU@` are not named

`upstream/sqlite3.pc.in:15` lists five `@LDFLAGS_*@` substitutions. Three of them
are named here, per target, from what the amalgamated C actually references:

* `-lm` — `ceil` and `floor` are called unconditionally at
  `src/sqlite3.c:136436-136437`, wrapped in `xCeil`/`xFloor` only because "on
  some systems, ceil() and floor() are intrinsic function. You are unable to take
  a pointer to these functions" (`src/sqlite3.c:136431-136435`). `src/shell.c:8201-8202`
  does the same, so the shell needs it too. Not named on Windows, where the maths
  are in the C runtime, or on WASI, whose libc carries them with no separate
  `libm` to name.
* `-ldl` — `dlopen` at `src/sqlite3.c:47240`, under
  `#ifndef SQLITE_OMIT_LOAD_EXTENSION` (`:47232`). Not named on Darwin (in libc),
  not on Windows (`LoadLibrary`, `src/sqlite3.c:31044`), and not on WASI, where
  upstream's own arm defines the macro (`src/sqlite3.c:11679-11681`).
* `-lpthread` — where `SQLITE_MUTEX_PTHREADS` selects the pthread mutex:
  `src/sqlite3.c:30623-30625` includes `<pthread.h>` and `:23543` takes the
  pthread arm of the factory. Not on Windows, not on WASI.

The other two are absent because nothing this configuration compiles references
them. `grep -c 'zlib.h' src/sqlite3.c` is **0** and
`grep -c 'unicode/ucnv.h' src/sqlite3.c` is **0**. Naming a `-lz` with no
declaration behind it would be a link-line claim with nothing to support it.

This is `SOURCE-CONFIRMED` by reading the source, and it is not yet confirmed by
a link. Whether these three resolve on each of the six baseline targets is
`PENDING-VERIFICATION` and belongs to `zig build check`.

## 6. One version in three places, and the check that keeps them there

`build.zig.zon`'s `.version`, `src/sqlite3.h`'s `SQLITE_VERSION` and
`upstream/VERSION` are three separate texts that all say `3.53.4`, and
`build.zig` refuses to configure when the manifest and the header disagree.
`tools/check-provenance.sh` adds the third comparison — `upstream/VERSION` — and
the `SQLITE_VERSION_NUMBER` line, so a release bump cannot land in two of the
three.

The Fossil check-in name is a fourth place, and `tools/check-provenance.sh`
recomputes it rather than trusting the record.

## 7. The shared object's ABI name, and the one field that cannot carry it

`upstream/main.mk:1554-1563` installs `libsqlite3.so.$(PACKAGE_VERSION)` with
`libsqlite3.so` and `libsqlite3.so.0` links, and `upstream/main.mk:1516-1519`
says why the `0` link exists at all: "The link named libsqlite3.so.0 is provided
in an attempt to reduce downstream disruption when performing upgrades from
pre-3.48 to a version 3.48 or higher."

Zig's `Compile.version` is a single triple from which it derives both the file
name (`libsqlite3.so.MAJOR.MINOR.PATCH`) and the soname (`libsqlite3.so.MAJOR`).
Upstream wants file name `libsqlite3.so.3.53.4` and soname `libsqlite3.so.0`,
which are not derivable from one triple. `build.zig` keeps the **soname**, and
says why in the module comment: it is the field a consumer binary records in
`DT_NEEDED` and the one that has to agree with every other SQLite on the machine.
The delivered object is therefore `libsqlite3.so.0.53.4`. A C consumer writes
`-lsqlite3` and never sees the difference.

There is no version script, and the reason is upstream's own header:
`src/sqlite3.h:26-31` says "If a C-function, structure, datatype, or constant
definition does not appear in this file, then it is not a published API of
SQLite". Every declaration the header carries is exported, and so is every
internal symbol the amalgamation defines — which is what a `.so` built from one
translation unit contains anyway. A Lua-style version script is the right answer
for a library with internal namespaces (`luaS_*`, `luaC_*`) and the wrong answer
for this one.

## 8. The public-domain term, and the three files whose term is not stated here

SQLite's term is a **dedication**, not a licence. `NOTICE.md` states it from the
files: `upstream/LICENSE.md`'s prose, the per-file blessing at
`src/sqlite3.h:1-8` and `src/sqlite3ext.h:1-8`, and `upstream/README.md`'s own
"## Public Domain" section.

`upstream/LICENSE.md` also draws a line this tree sits astride. It says the
repository contains "a (relatively) small amount of non-public-domain code used
to help implement the configuration and build logic" — the autosetup system,
"mostly" in `autosetup/`, and the legacy `autoconf/` directory — with
BSD-style licences, and that "attribution may be required to reuse or republish
the configure and build scripts". It also says what that means for a
redistributor: "None of the non-public-domain code ever actually reaches the
build products, such as `sqlite3.c`, however, so no attribution is required to
use SQLite itself."

Three files in `upstream/` are on the configure side of that line:
`auto.def` (the project's autosetup configuration script),
`Makefile.in` and `main.mk`. **Their exact term cannot be read out of this tree**,
and `NOTICE.md` records them as "not stated in this file" rather than as public
domain. The autosetup licence text upstream points at lives in `autosetup/LICENSE`,
which is in neither release archive and is therefore absent here.

What this fork does with them: nothing executable. No step runs `auto.def`, reads
`Makefile.in` or `main.mk` as a build input, or installs any of them.
`build.zig` cites `main.mk` and `Makefile.in` **by line**, as text in comments.
`sqlite3.pc.in` is read as a template for the generated `.pc`. A consumer who
republishes those three files, rather than compiling SQLite with them, is the one
who needs to look at `autosetup/LICENSE`.

## 9. `Db.open` returns a union, and that is not decoration

`sqlite3_open_v2` has three outcomes and one of them hands back a live handle.
`src/sqlite3.h:3725-3726` says upstream returns it that way, and the reason is
printed there: the message the caller needs lives in the connection's own
memory.

Collapsing the three into an error set would mean either closing the handle
before the caller read the message — freeing the string they need — or handing
back a connection nobody asked for and nobody documented. So `OpenResult` is
`.ok` / `.failed` (carrying the live `Db` and the code, which **must** be closed)
/ `.no_connection` (`src/sqlite3.h:3721-3723` names this case as SQLite being
unable to allocate the object; nothing was opened and there is nothing to close).

`tests.zig` covers the `.failed` case by opening a path that cannot be opened and
reading the message back through the handle upstream returned.

## 10. `Statement.finalize` takes the statement by value

`sqlite3_stmt` has one owner. A `Statement` copied by value has two owners of one
handle, and `sqlite3_finalize` on the second reaches freed memory. Taking the
statement **by value** makes the handle consumed by the call, so a caller cannot
finalize the same value twice, and `defer statement.finalize() catch {}` is safe
without a flag. It is also why `Db.exec` can finalize internally on the error
path and still leave the caller with nothing to clean up.

The `catch` is not optional. `sqlite3_finalize` can return a code, and a `defer`
cannot return one; swallowing the code is better than leaking the statement, and
the library's own diagnosis is still available through the connection.

## 11. The error set is cut at what this code checked

`Error` names conditions `tests.zig` and `zig/root.zig` actually test: a prepare
that did not return `SQLITE_OK`, a bind that failed, a column that is SQL NULL, a
column index outside `columnCount()`, an open-flag combination
`src/sqlite3.h:3741-3744` says is invalid.

It is **not** SQLite's result-code taxonomy, which runs to about a hundred
members (`sqlite3_errstr`). A Zig error set is an upper bound, and one that large
would say nothing about which code this code can hit. The cut is compensated
rather than hidden: `Db.errcode()`, `Db.extendedErrcode()`, `Db.errStatus()`,
`Db.errmsg()` and `sqlite.errstr(code)` are all public, so the exact code is
always one call away. `tests.zig` checks the `Status` enum against the header's
values one for one, which is where the taxonomy lives.

## 12. Memory inside SQLite is SQLite's

`sqlite3_malloc64` (`src/sqlite3.h:3319`) and `sqlite3_free` (`:3322`) hand out
and take back memory from whatever allocator the library was built with. No Zig
allocator is in that path. A test framework cannot supply a leak oracle for
memory a third-party allocator owns, so no test here claims to.

What can be said, and is: the largest single thing that allocator does is create
and drop a connection, and the tests do exactly that, on the success and the error
path alike. That is the whole of what this SDK can observe about it, and
`runtime/library.zig`'s load-time check says the same thing about a runtime-loaded
provider rather than claiming more.

## 13. The public-domain dedication for this fork's own files

The owner authorized per-project licensing for fork-authored additions, with the
term chosen per project to match that project's primary upstream terms. SQLite's
primary term is a public-domain dedication, so that is the term this fork's files
carry, in `FORK-LICENSE.md`, with `LicenseRef-PublicDomain` as the SPDX
identifier.

The `LicenseRef-` wrapper is deliberate and is **not** a variant grant. SQLite's
term is not one of the OSI-approved licences an SPDX scanner resolves by bare
identifier, so a bare `PublicDomain` would assert a registered identifier this
grant is not. Twenty fork-authored files carry the tag; the rest are named in
`NOTICE.md` with the reason they do not.

## 14. Open, for the driver

Each item is stated as what is missing, not as a failure.

1. **Most of the gate list is now run; the system and second-mode gates are
   not.**
   `zig build`, `test`, `smoke`, `oracle`, `consumer` and `check` across all six
   targets were run in this wave against Zig 0.16.0 and every one exited zero.
   Still `PENDING-VERIFICATION`, with no result for any of them in this tree:
   `test` in ReleaseSafe, the installed-tree C consumer, the pkg-config
   consumer, `-Dsystem=true` / `-fsys=sqlite3`, the Nix variants, and
   `zig build -Dlinkage=dynamic`, which cannot configure at all today - see
   item 8. The 53-platform `cross-test` matrix has since been run and is item 9.
2. **`.fingerprint` is now in both manifests, and both values are the
   toolchain's.** `build.zig.zon` carries `0x6edcd71155f49d5f` and
   `consumer/build.zig.zon` carries `0xb7655c6ba16d5c86`, each taken from the
   compiler's own diagnostic rather than written by hand, which is the outcome
   item 2 used to record as pending. Nothing in this tree derives either value.
3. **`README.upstream.md` was created by this wave.** `build.zig.zon`'s `.paths`
   names it, and `zig fetch` hashes every named path, so its absence would fail
   the fetch rather than record an absence. It is a byte copy of
   `upstream/README.md` (21 098 bytes, sha256
   `f3f527d4deea6ee8e8a552aa481b920aedbc91c95dbddd34100eb9ffb1efb897`) and is not
   a 1300th upstream file: `UPSTREAM.sha256` records `upstream/README.md` alone,
   and `tools/check-provenance.sh` is what proves the copy has not drifted.
   **Note the internal inconsistency this exposed:** `build.zig.zon`'s comment on
   that path says the preserved README "lives at `upstream/README.md`", while the
   `.paths` entry on the next lines names `README.upstream.md`. Both are now true
   and both are checked, but a reader of that manifest alone would not know which
   file is which.
4. **416 of the 1285 files under `test/` do not match upstream's own Fossil
   manifest, and the cause is not established.** This is the one substantive open
   question in the tree. What was checked and ruled out:
   * it is not a line-ending difference — those files contain no CRLF, and
     converting LF to CRLF reproduces none of them;
   * it is not a missing or extra final newline;
   * it is not trailing-whitespace normalisation;
   * it is not Fossil `$Id$` keyword expansion or its collapse;
   * it is not a permutation: no file's on-disk bytes hash to any other path's
     entry in the manifest, and no manifest hash appears twice.

   Nothing in this package is affected — the suite is unedited, uncompiled and
   unrun. It matters only to a wave that wants to *run* it, which would first
   need to establish the difference against a fresh download of
   `sqlite-src-3530400.zip`.
   `tools/check-provenance.sh` reports the count on every run and does not fail
   on it, because a gate that is permanently red on an unexplained difference
   hides real edits behind a known failure.
5. **`tools/check-provenance.sh` was exercised while it was being written.** Its
   eight checks were run against this tree at authoring time and the output was
   read; that is a source-integrity script reading files, not a build gate. It
   has not been run by the driver, and nothing in `README.md` claims otherwise.
6. **System mode is not gated in this wave.** `-Dsystem=true` and
   `-fsys=sqlite3` are wired through `b.systemIntegrationOption` and are
   `PENDING-VERIFICATION`. `build.zig`'s module comment states the rule they rest
   on: system mode translates the real selected system headers, and bundled
   new-release headers against an older installed library compile and fail
   silently.
7. **The `wasm32-wasi` cell has a documented behavioural difference, not a
   refusal.** Upstream's own arm (`src/sqlite3.c:11676-11685`) compiles that
   target with `SQLITE_THREADSAFE 0` and `SQLITE_OMIT_LOAD_EXTENSION`, so the
   library there is single-threaded and refuses to load extensions. `tests.zig`
   does not pin a mode: it accepts any of the three the header defines
   (`src/sqlite3.h:259` — 0 single-thread, 1 serialized, 2 multi-thread) and then
   opens a *second* connection on the same thread and writes through it, which is
   the observable half of "usable in whichever mode this target selected". A WASI
   cell therefore passes with `0`, and what it prints is the library's own answer
   rather than a constant compiled into the test. What a given `cross-test` cell
   does with that is the gate's fact to record.
8. **`zig build -Dlinkage=dynamic` cannot configure, and the cause is in
   `check`, not in the delivery.** `deliveredLinkage` refuses a shared object on
   a target whose OS has no dynamic linker (`build.zig:1613`), and `check`
   configures all six rows at build time, so the `wasm32-wasi` row panics before
   anything is compiled:

       thread N panic: zig build: -Dlinkage=dynamic was asked for wasi, whose
       operating system has no dynamic linker, so no shared object can be built
       or loaded there.

   That contradicts the module comment beside `check`, which says `check` is not
   the step that refuses. Two readings are available and the choice is the
   driver's: either the check rows resolve their own per-target linkage, so the
   matrix still walks all six targets, or the published graph alone applies
   `deliveredLinkage`. Neither reading drops a target. Until it is decided, the
   shared delivery this package documents cannot be produced at all, which also
   means `zig build consumer -Druntime=true` has no provider to load from this
   tree: a system `libsqlite3.so.0` is refused with `MissingSymbol`, correctly,
   because it does not export all 366 declarations this header names.

   Two further facts about that route, both observed rather than assumed. It
   compiles and links now; before this wave it did not compile at all. And the
   sentinel `SQLITE_TRANSIENT` is the one thing the routed route cannot carry on
   a target whose function pointers are required to be aligned, because the
   generated table types the destructor as the header's own function pointer
   (`zig/root.zig`, `transient`) and Zig will not hold the address `-1` in one.
   The routed branch therefore needs `@alignOf(c.sqlite3_destructor_type) == 1`,
   which is a compile-time answer on every host the route is built for, and the
   linked route - all six `check` targets - does not have the restriction.

9. **The 53-platform `cross-test` matrix now has an observed run, and it is red
   on all eighteen NetBSD and OpenBSD rows for one reason this fork owns.**
   Run `20261005-191626-52905-3050` on 2026-10-05 from this package root with
   Zig 0.16.0 and `--jobs 8 --build-jobs 8`, using this tree's own
   `cross-test.profile.sh` and no target list. The harness exited **1** over
   `target_count 53`: **20 pass** (`x86_64-linux` native, nineteen under
   QEMU-user, each `run test sqlite3-tests 25 pass (25 total)`), **15
   `build_only`** (compiled, no executor on this host, never executed), **18
   build failures**, **0 partial**, **0 refused**, and no cell that compiled and
   then failed its run. Receipt:
   `$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/sqlite/cross-test-summary.json`
   with one `build-<target>.log` per cell under
   `…/cross/sqlite/runs/20261005-191626-52905-3050/`.

   **Condition.** `Platform.forTarget` (`build.zig:498-561`) has one arm for
   every Unix that is not Windows, WASI or Darwin, and the arm sets
   `.separate_dl = true` (`build.zig:554-561`) on the reasoning recorded in the
   comment at `build.zig:549-553`, which reads "Every other Unix — Linux, the
   BSDs, Solaris, illumos, AIX". That flag is what puts `-ldl` on the compile
   line (`build.zig:857-859`, `build.zig:919-921`) and into the installed
   `sqlite3.pc` (`build.zig:1278`).

   **Symptom.** All nine NetBSD rows and all nine OpenBSD rows stop in
   `compile lib sqlite3` with the same line and nothing else:

       error: unable to find dynamic system library 'dl' using strategy 'paths_first'. searched paths: none

   `Build Summary: 2/6 steps succeeded (1 failed)`; the harness reports
   `build=fail run=not_run reason=build_failed`. No NetBSD or OpenBSD cell
   reached `translate-c` output, the test binary, or any test.

   **What is established and what is not.** Observed and consistent across all
   eighteen: the message above, and the six FreeBSD rows compiling with the same
   `-ldl`, so the arm is right for FreeBSD and wrong for NetBSD and OpenBSD.
   Observed from the pinned toolchain: `lib/libc/netbsd/lib` and
   `lib/libc/openbsd/lib` contain only `csu/`, and no `libdl.so` exists anywhere
   under `lib/libc/` for any BSD — which does **not** by itself explain the
   FreeBSD difference, so it is recorded as what is in the tree, not as the
   mechanism. Not established, and not to be asserted: which operating systems
   Zig 0.16.0 offers a `dl` search path for. That policy lives in the compiler
   binary and is not shipped as source, so the observed diagnostic is the
   evidence and nothing stronger is claimed here. Also not established: whether
   `-lm` and `-lpthread` are needed on those two operating systems, because the
   build stopped at `-ldl` and never got to them.

   **Fix, not applied.** A NetBSD/OpenBSD arm beside the Darwin one at
   `build.zig:537-548`, setting `.separate_dl = false`, is the shape the cause
   calls for; whether `separate_pthread` also has to change there is part of the
   same unproven question. It is not applied here because this note records an
   observation, and a correction wave owns the edit and the fresh gate that has
   to follow it. **No upstream file is involved** — the cause is entirely in
   this fork's build graph, and nothing under `src/` was touched to find it.

   **Targets bound.** `zig` 0.16.0 (the pinned host-scratch compiler), the
   published 53-platform Tier 1/2 table as `cross-test` resolves it, this host's
   QEMU-user set and its absent Wine and wasmtime. On a host with Wine or
   wasmtime the two Windows rows and `wasm32-wasi` would move from `build_only`
   to executed cells, and their outcomes are not known from this run.
