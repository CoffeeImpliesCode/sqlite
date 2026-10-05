# Upstream

Which upstream this SDK is built from, what was taken from it byte for byte,
what is *not* claimed because no copy of it is in this tree, and what was not
taken at all.

## Canonical source

| | |
|---|---|
| Project | SQLite, the SQL database engine |
| Authoritative site | <https://sqlite.org/> |
| Upstream VCS | Fossil, <https://sqlite.org/src/timeline> |
| Release | SQLite 3.53.4, 2026-07-24 |
| Fossil check-in | `bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc` |
| Fossil tag | `version-3.53.4` |
| Fossil branch | `branch-3.53` |
| Check-in date | `2026-07-24T19:02:57.525Z` |
| Artefact A | `sqlite-amalgamation-3530400.zip` → `src/` |
| Artefact B | `sqlite-src-3530400.zip` → `upstream/` and `test/` |

Every one of those values is read out of a file in this repository, not
recalled and not looked up:

* `upstream/manifest.uuid` — the check-in name, one line.
* `upstream/manifest.tags` — `tag release`, `tag branch-3.53`,
  `tag version-3.53.4` and `branch branch-3.53`.
* `upstream/manifest` — its `D` card is `2026-07-24T19:02:57.525`, and its
  `U` card names the user `drh`.
* `src/sqlite3.h:149-154` — `SQLITE_VERSION "3.53.4"`,
  `SQLITE_VERSION_NUMBER 3053004`, `SQLITE_SOURCE_ID "2026-07-24 19:02:57
  bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc"`,
  `SQLITE_SCM_BRANCH "branch-3.53"`, `SQLITE_SCM_TAGS "release
  version-3.53.4"`, `SQLITE_SCM_DATETIME "2026-07-24T19:02:57.525Z"`.
* `upstream/VERSION` — the five bytes `3.53.4`.
* `src/sqlite3.c:20-21` — "The content in this amalgamation comes from Fossil
  check-in bf7c7f30031888f4e796e429ab3978879485 with changes in files:",
  followed by an **empty** list.

That last one is worth stopping on, because it is upstream stating that the
amalgamation in this archive differs from that check-in in no file at all. The
release is the check-in.

`SOURCE-CONFIRMED`: every row above is a value read out of the named file in
this tree. Nothing here was fetched, and no remote was queried.

## The release archives' own digests are not in this tree

**Neither archive's sha256 is recorded anywhere in this repository, and this
file therefore does not state one.** Both zips were unpacked into `src/`,
`upstream/` and `test/`; no copy of either archive is present to hash, and an
unobserved digest is not an identifier this record is permitted to invent
(`AGENTS.md` rule 3). `UPSTREAM.sha256` records the 1299 individual files
instead, which is a strictly finer check: it detects a change to any one file
rather than only to the archive as a whole.

The parent gate owns re-downloading either archive and recording its published
digest if one is wanted; that is a fetch, and this tree performs no fetch.

## What was verified, and how

Upstream ships a documented integrity method, and `upstream/README.md`
("## Verifying Code Authenticity") states it: "The `manifest` file at the root
directory of the source tree contains either a SHA3-256 hash or a SHA1 hash for
every source file in the repository. The name of the version of the entire
source tree is just the SHA3-256 hash of the `manifest` file itself, possibly
with the last line of that file omitted if the last line begins with `# Remove
this line`. The `manifest.uuid` file should contain the SHA3-256 hash of the
`manifest` file."

Computing that over `upstream/manifest` as shipped, with its final
`# Remove this line…` comment omitted, gives

```
bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc
```

which is exactly `upstream/manifest.uuid`, exactly the check-in in
`src/sqlite3.h:151`, and exactly the check-in `src/sqlite3.c:20-21` names.
`tools/check-provenance.sh` recomputes it, so the release metadata, the check-in
identity and the compiled amalgamation are bound together by a check rather
than by a claim in this file.

The per-file half of the same method was also run, and its result is reported
here because it is not uniform:

* **9 of the 10 files in `upstream/` match the `sha3` the Fossil manifest
  records for them**, byte for byte: `LICENSE.md`, `Makefile.in`, `README.md`,
  `VERSION`, `auto.def`, `main.mk`, `sqlite3.pc.in`. The two that do not appear
  in the manifest at all are `manifest.tags` and `manifest.uuid` — they are
  Fossil's own metadata about the manifest, and a manifest does not list
  itself.
* **`src/sqlite3ext.h` matches** the manifest's recorded hash for that path.
* **`src/sqlite3.c`, `src/sqlite3.h` and `src/shell.c` have no manifest entry**,
  and are not supposed to: they are generated artefacts. `upstream/README.md`
  ("### Generated Source Code Files" and "### The Amalgamation") says `sqlite3.h`
  is generated from `src/sqlite.h.in`, `./manifest.uuid` and `./VERSION` by
  `tool/mksqlite3h.tcl`, that `shell.c` "is transformed … as part of the build
  process" from `src/shell.c.in`, and that the amalgamation is produced by
  `tool/mksqlite3c.tcl`. Upstream ships the generator's output in the release
  archives and does not check the output in.
* **869 of the 1285 files under `test/` match** the manifest's recorded hash;
  **416 do not**, and **the cause is not established**. The set was compared
  file by file; it is not a line-ending difference (the tree has no CRLF in
  those files), not a trailing-newline difference, not a whitespace-normalisation
  difference, and not a Fossil `$Id$` keyword-expansion difference; and the
  bytes on disk hash to no other file's entry in the manifest, so it is not a
  permutation of the manifest's own contents either.

That last item is an honest open question about this tree, not a claim about
SQLite. It changes nothing about what this package builds — the whole suite is
vendored unedited, compiled by nothing, and run by nothing (see below) — but a
future wave that wants to *run* `test/` should establish the difference against a
fresh download of `sqlite-src-3530400.zip` before treating this tree as a
bit-faithful copy of the release. `FORK-NOTES.md` carries it as an open item.

## What upstream is

A complete, self-contained SQL database engine: an SQL parser, a code
generator, a bytecode virtual machine, a pager and B-tree storage layer, a
pluggable OS interface, a query planner and an incremental optimizer. As
imported here it is **four files and one translation unit**, because that is what
`sqlite-amalgamation-3530400.zip` contains.

`src/sqlite3.c` is 269 649 lines and 9 515 341 bytes. `src/sqlite3.h` is 14 349
lines. `src/shell.c` is 37 415 lines and is the `sqlite3` command-line shell,
not part of the library. `src/sqlite3ext.h` is 739 lines and defines the
interface a loadable extension implements.

There is no external dependency in this configuration. `build.zig` defines no
`SQLITE_*` macro at all, and records why, reading the decisions out of upstream's
own source rather than asserting them: OS selection at `src/sqlite3.c:16538-16548`,
`SQLITE_THREADSAFE` defaulting to 1 at `src/sqlite3.c:15106-15111`, the WASI arm
at `src/sqlite3.c:11676-11685`, and the unreachable `sqlite_cfg.h` include at
`src/sqlite3.c:14685`. `grep -c 'zlib.h' src/sqlite3.c` is 0 and
`grep -c 'unicode/ucnv.h' src/sqlite3.c` is 0, which is why
`upstream/sqlite3.pc.in:15`'s `@LDFLAGS_ZLIB@` and `@LDFLAGS_ICU@` are not named
on any link line.

**What this configuration does not have** is a build-time fact rather than an
omission: no `SQLITE_ENABLE_FTS5`, no `SQLITE_ENABLE_JSON1`, no
`SQLITE_ENABLE_MATH_FUNCTIONS`, no `SQLITE_ENABLE_RTREE`, no
`SQLITE_ENABLE_COLUMN_METADATA`. `PRAGMA compile_options` reports that at run
time. A consumer that needs one of those needs a differently configured SQLite,
which is a build-time choice.

## Upstream's build system, and why this tree does not run it

SQLite is built by `autosetup`. `upstream/README.md` ("## Compiling for
Unix-like systems") says to run `../sqlite/configure` and then `make`, and that
"The configure script uses autosetup". `upstream/Makefile.in` is 347 lines and
its line 347 is `include $(TOP)/main.mk`; `upstream/main.mk` is 2 526 lines and
carries the actual targets. `upstream/auto.def` is 69 lines and is the project's
autosetup configuration script.

This package runs **none** of that: no `tclsh`, no `jimsh`, no `make`, no
`configure`, no `autosetup`, and no download. `build.zig` compiles the same
single translation unit upstream's own `upstream/main.mk:2094` names for the
amalgamation — that target's prerequisite list is exactly `sqlite3.c
sqlite3.h shell.c sqlite3ext.h`, which is the four files under `src/`.

That is not a substitute for the canonical tree, and the difference is worth
stating rather than glossing. Upstream's own README calls the amalgamation
"the recommended way of using SQLite in a larger application" and explains that
combining the files lets the compiler do cross-procedure analysis it cannot do
otherwise. The amalgamation here is upstream's own generator's output, shipped
in upstream's own release archive, with the check-in it came from recorded in
its own first comment block — not a hand-written stand-in and not a
re-implementation.

## There is an upstream test suite, and this package does not run it

Unlike a Lua or a regex release, this one carries its suite: `test/` is
vendored from `sqlite-src-3530400.zip` whole — **1285 files, 87 774 656 bytes**
— the TCL scripts under `test/*.test` and `test/*.tcl`, 32 C support programs
(the fuzzers `test/optfuzz.c` and `test/dbfuzz.c`, the thread testers
`test/threadtest1.c` … `threadtest5.c`, the stress drivers `test/tt3_*.c`,
`test/kvtest.c`, `test/testloadext.c` and their companions), and the generated
`fuzzdata*.db` inputs that dominate the byte count. Nothing is dropped and
nothing is edited; `UPSTREAM.sha256` records every file and
`tools/check-provenance.sh` fails if the set changes.

This package does **not** build or run it, and no step pretends otherwise. The
blocking fact is structural and worth being exact about, because it is easy to
assume the TCL scripts are self-contained and are not.

`test/testrunner.tcl` drives the suite through a `testfixture` binary, and
`upstream/main.mk:1799` builds that from `TESTFIXTURE_SRC`, which
`upstream/main.mk:1794-1796` defines as `$(TESTSRC) tclsqlite-ex.c` plus
`sqlite3.c` — where `$(TESTSRC)` (`upstream/main.mk:722`) is a list of
`src/test1.c`, `src/test2.c` and the rest of the canonical `src/` tree, together
with `src/tclsqlite3.c`. **None of those files is in this tree.** The four files
under `src/` are the amalgamation's own; the ten under `upstream/` are release
metadata; the canonical per-module `src/` tree — the one upstream's test harness
is compiled from — was not imported here, and `upstream/manifest` records it as
2205 files of which this tree keeps 10.

Two further requirements sit behind that one: TCL 8.6 development libraries
(`upstream/README.md`: "many makefile targets require a 'tclsh' TCL interpreter
version 8.6 or later"), and `autosetup` plus `make` to generate the rest
(`parse.c`, `opcodes.c`, `keywordhash.h`, `pragma.h`). Building it would mean
re-introducing exactly the build system this package replaces. So `build.zig` has
no `upstream-test` step, fetches nothing to stand in for one, and `README.zig.md`
records which independent known answers and which upstream interop check the
package's own gates use instead.

The replacement proofs are small and honest about being small:

* `tests.zig` seeds twelve rows and checks a grouped reduction against a table
  hand-computed from them, and against a second implementation that does the same
  arithmetic in Zig with no SQL at all.
* `tools/check-oracle.sh` runs **the same SQL text** through upstream's own
  `sqlite3` shell — `src/shell.c`, a different C client with its own SQL front
  end and its own output formatting — and compares the result byte for byte with
  `tools/fixture/expected.tsv`.

Neither is a substitute for 1285 upstream test files, and neither is described
as one.

## Nothing is generated at build time from the native source

The four files under `src/` are release artefacts, checked in upstream and
shipped by upstream. This build generates no C source, no header and no table
from them, and it runs no upstream generator to produce them.

The build *does* generate three files, none of which is a second source of truth
for the C:

* `lib/pkgconfig/sqlite3.pc`, written by `build.zig`'s `add_pkg_config` from the
  layout `build.zig` installed, relocatable through
  `prefix=${pcfiledir}/../..`;
* under `-Druntime=true` only, the runtime dispatch and its patched translation,
  written through `Run.addOutputFileArg` so they land in the build cache rather
  than in this tree, and built from the translation of `zig/translate.h` and
  upstream's own headers that this same build has just produced for the target
  being built.

## The preserved upstream README

`sqlite-src-3530400.zip` carries a file called `README.md`, which is upstream's
own source-repository note and **not** a fork README. It is preserved here
twice, unaltered:

* `upstream/README.md` — the imported original, exactly as the archive carries
  it, and recorded in `UPSTREAM.sha256` as an upstream file like every other.
* `README.upstream.md` — the same bytes under the name the rest of this
  repository uses for a preserved upstream README.

Both are 21 098 bytes with sha256
`f3f527d4deea6ee8e8a552aa481b920aedbc91c95dbddd34100eb9ffb1efb897`, and
`tools/check-provenance.sh` fails if they ever differ. The canonical fork
document is [`README.md`](README.md).

## Import mechanism

Two release archives, unpacked. There is no upstream Git history in this tree
and no Git commit SHA to record, and none is invented: SQLite is not developed in
Git, and upstream's own README warns against using a mirror's object names in
place of Fossil's ("Always use the official name, not the Git-name, when
communicating about an SQLite check-in"). The Fossil check-in name *is* the
identity, and it is recorded in three independent places in this tree.

There is no patch series and no patch: the tree either matches the archives or a
deviation is recorded. `UPSTREAM.sha256` is the check that it does.

If a future wave re-syncs to another release, the correct sequence is: download
both new archives, record their published digests, replace the imported files,
update `UPSTREAM.sha256`, `UPSTREAM.md`, `NOTICE.md` and `README.md`, and add a
numbered `CHANGELOG.md` entry — in one change.

## Third-party material in this repository

None. There is no vendored dependency, no generated table and no downloaded
header. Every file here other than the 1299 upstream files listed above, and
`README.upstream.md`'s copy of one of them, was written for this fork. The
1285-file upstream suite is upstream's, not a third party's.