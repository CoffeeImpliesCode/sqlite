# Notice

Two separate things are recorded here: what the canonical native source is and
which term covers each of its files, and what this fork wrote on top of it.
[`FORK-LICENSE.md`](FORK-LICENSE.md) carries the grant for the second group.

## The upstream term

SQLite is **public domain**. That is a dedication, not a permissive licence, and
this tree states it the way upstream writes it rather than paraphrasing it into
a licence name. Two places in this tree carry it:

* `upstream/LICENSE.md` — the prose statement, headed "SQLite Is Public
  Domain", with the blessing quoted in full and the affidavit note ("The authors
  have submitted written affidavits releasing their work to the public for any
  use").
* The per-file blessing at the head of the source files themselves —
  `src/sqlite3.h:1-8` and `src/sqlite3ext.h:1-8`, and the same block 144 times
  inside `src/sqlite3.c` and 31 times inside `src/shell.c`, once per original
  file those amalgamations were concatenated from.

`upstream/README.md` says the same in one line under "## Public Domain": "The
SQLite source code is in the public domain. See <https://sqlite.org/copyright.html>
for details." That README also states what public domain means *for upstream's
own workflow*: because a pull request could carry a copyright, "we do not
normally accept pull requests". Nothing in this fork is a pull request and no
fork-authored file is claimed under upstream's dedication; see
`FORK-LICENSE.md`.

The blessing itself, as `upstream/LICENSE.md` quotes it and as every
public-domain source file in `src/` repeats it at its head:

> The author disclaims copyright to this source code.  In place of a legal
> notice, here is a blessing:
>
>   *   May you do good and not evil.
>   *   May you find forgiveness for yourself and forgive others.
>   *   May you share freely, never taking more than you give.

`upstream/LICENSE.md` also says what the term is **not**: it is not an
attribution obligation. "None of the non-public-domain code ever actually
reaches the build products, such as `sqlite3.c`, however, so no attribution is
required to use SQLite itself." There is therefore no upstream notice a
redistributor of the library itself is obliged to carry — and this package
installs the two texts anyway, because carrying them costs nothing and a
private repository removes no obligation.

## Inventory of the upstream files

1299 files, 99 153 005 bytes, digests in
[`UPSTREAM.sha256`](UPSTREAM.sha256).

| Path | Files | Bytes | What it is | Term |
|---|---:|---:|---|---|
| `src/sqlite3.c` | 1 | 9 515 341 | upstream's amalgamation of the core library | public domain |
| `src/sqlite3.h` | 1 | 690 838 | the generated public header | public domain |
| `src/sqlite3ext.h` | 1 | 39 175 | the loadable-extension interface header | public domain |
| `src/shell.c` | 1 | 1 185 915 | the amalgamated `sqlite3` CLI | public domain |
| `upstream/` | 10 | 307 080 | release metadata and the two upstream makefiles | see below |
| `test/` | 1285 | 87 774 656 | upstream's TCL test suite: its TCL scripts, its C support programs and its `fuzzdata*.db` inputs | public domain |

`upstream/LICENSE.md` states the scope of the public-domain grant in its own
words, and the boundary it draws is a directory list:

* "All of the primary SQLite source code files found in the `src/` directory"
* "All of the test cases and testing code in the `test/` directory"
* "All of the SQLite extension source code and test cases in the `ext/`
  directory" — not vendored here; `ext/` is not part of either release archive
  this tree was built from
* "All code that ends up in the `sqlite3.c` and `sqlite3.h` build products"
* "All of the code used to compile the `command-line interface`" and "All of
  the code used to build various utility programs"

So `src/` and `test/` are inside the dedication by name, not by inference, and
the fact that `src/sqlite3.c`, `src/sqlite3.h` and `src/shell.c` are *generated*
files does not move them outside it: upstream places generated build products
inside the same grant.

### The `upstream/` directory, file by file

`upstream/` holds ten files from the `sqlite-src-3530400.zip` archive. They are
not all the same kind of material, so they are not given one label.

| File | Term | Notice in the file |
|---|---|---|
| `upstream/LICENSE.md` | the public-domain dedication itself | the whole file |
| `upstream/README.md` | public domain | "## Public Domain" section |
| `upstream/VERSION` | public domain | none — 5 bytes, `3.53.4` |
| `upstream/manifest` | public domain | none — Fossil's own file inventory |
| `upstream/manifest.tags` | public domain | none — Fossil's own tag list |
| `upstream/manifest.uuid` | public domain | none — Fossil's own check-in name |
| `upstream/Makefile.in` | **not stated in this file** | none — a makefile with no copyright line |
| `upstream/main.mk` | **not stated in this file** | none — a makefile with no copyright line |
| `upstream/auto.def` | **not stated in this file** | none — an autosetup configure script |
| `upstream/sqlite3.pc.in` | **not stated in this file** | none — a pkg-config template |

The three "not stated" rows are recorded as unknown rather than as public
domain, and the reason is specific rather than cautious boilerplate:

`upstream/LICENSE.md`'s own section on non-public-domain code names what is
included "for convenience" to implement `./configure && make`: the autosetup
configuration system "contained (mostly) in the autosetup/ directory, but also
includes the `./configure` script at the top-level of this archive", with
"BSD-style licenses", and "some of the configuration software found in the
legacy autoconf/ directory". `upstream/auto.def` is the autosetup configure
script this project ships (its first line is `use sqlite-config`, and
`upstream/README.md` states "The configure script uses
autosetup"), so it is configure-side material of the kind `LICENSE.md`
describes. `upstream/Makefile.in` and `upstream/main.mk` are upstream's own
build files for the canonical `src/` tree.

**The exact term for those three cannot be read out of this tree**, and this
record does not guess it. The autosetup licence text upstream points at lives in
`autosetup/LICENSE`, a file that is in neither release archive this repository
vendors and is therefore absent here. What *is* stated in the files this tree
carries is that such code is "BSD-style", that "anyone is free to use any of the
code in this source repository for any purpose, though attribution may be
required to reuse or republish the configure and build scripts", and — the
part that matters for a package that ships binaries — "None of the
non-public-domain code ever actually reaches the build products, such as
`sqlite3.c`".

Nothing in this fork executes `upstream/auto.def`, reads `upstream/Makefile.in`
or `upstream/main.mk` as a build input, or ships any of them into an installed
tree. `build.zig` cites `main.mk` and `Makefile.in` **by line**, as the text
they are, in comments; `upstream/sqlite3.pc.in` is read as a template for the
generated `sqlite3.pc`, and its own four `@…@` substitutions are `@prefix@`,
`@exec_prefix@`, `@libdir@`, `@includedir@` and `@PACKAGE_VERSION@`. A consumer
who republishes these three files, rather than compiling SQLite with them,
falls inside the "attribution may be required" sentence quoted above.

## Per-file exceptions

Within the compiled library there are none: `src/sqlite3.c`, `src/sqlite3.h`,
`src/sqlite3ext.h` and `src/shell.c` are all inside the public-domain grant, and
the same is true of every one of the 1285 files under `test/`.

The exceptions this release does have are all **build-side and outside the
compiled core**, and they are recorded above rather than folded into one label:
the autosetup configure material, described in `upstream/LICENSE.md` as
BSD-style with attribution possibly required on republication, whose full text
is not present in this tree.

That is a statement about *this* release, not about all of SQLite's history or
about every SQLite-derived work in existence.

## What this fork changed in upstream files

**Nothing.** No file under `src/`, `upstream/` or `test/` has been edited.
`UPSTREAM.sha256` plus the exact-file-set check in `tools/check-provenance.sh`
are what make that claim checkable rather than asserted, and any future native
edit has to move those digests in the same change, with a numbered entry in
[`CHANGELOG.md`](CHANGELOG.md).

One upstream fact is verified here rather than assumed, and it is the strongest
integrity evidence this tree carries. `upstream/README.md` ("## Verifying Code
Authenticity") states the method: "The `manifest.uuid` file should contain the
SHA3-256 hash of the `manifest` file", where the trailing `# Remove this line`
comment is not part of the hashed text. That was computed over
`upstream/manifest` as shipped and equals `upstream/manifest.uuid`, which equals
the check-in named in `src/sqlite3.h:151`'s `SQLITE_SOURCE_ID` and in
`src/sqlite3.c:20-21`. `tools/check-provenance.sh` repeats the computation, so
the manifest, its recorded check-in name and the compiled amalgamation cannot
disagree without the gate noticing.

`STATUS`: `SOURCE-CONFIRMED` from the recorded digests and from that
self-hash. That is a claim about bytes and about what this file asserts about
them, not about a build, and **no build result is recorded here or anywhere in
this repository**. [`README.md`](README.md) marks every gate
`PENDING-VERIFICATION`, because the driver owns every run and none has been run
from this tree.

## Fork-specific notice

Every file below was written for this fork. None of it carries an upstream
copyright, no upstream permission is claimed over it, and it is released into
the public domain on the terms recorded in
[`FORK-LICENSE.md`](FORK-LICENSE.md):

* `build.zig`, `build.zig.zon`, `.gitignore`, `cross-test.profile.sh`,
  `.github/workflows/verify.yml`
* `zig/root.zig`, the typed facade, and `zig/translate.h`, the aggregate
  translation header this build runs `translate-c` over
* `tests.zig`, `smoke.zig`, `consumer/build.zig`, `consumer/build.zig.zon`,
  `consumer/src/main.zig`
* `runtime/` — the load-at-runtime route, as the six files it holds today.
  `loader.zig` is the reusable state machine and platform layer, holding no
  per-SDK name; `library.zig` is this SDK's descriptor, the namespaced
  synchronization binding and the one load-time check; `graph.zig` is the build
  half that wires them together and substitutes `createModule` for the
  translation's own; `generate.zig` is the build-time generator that writes the
  dispatch from the real translation output for the target being built, through
  `Run.addOutputFileArg`, so the generated file lands in the build cache and
  this directory holds no generated source. `sync.h` and `sync.c` are the two C
  files that give the loader its process-global mutex, condition variable and
  thread identity under an `RT_SYNC_PREFIX` this SDK sets to `sqlite_rt`
  (`runtime/graph.zig:117`, `runtime/graph.zig:248`); `sync.c` is compiled into
  the dispatch and `sync.h` is the only header the route compiles C against. All
  six are fork work under this grant; none of them is upstream material, and
  `sync.c` is not a substitute for any upstream unit.
* `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`
* `tools/check-provenance.sh`, and the fixture it and the tests share:
  `tools/fixture/aggregate.sql`, `tools/fixture/expected.tsv` and
  `tools/check-oracle.sh`
* this file, `README.md`, `README.zig.md`, `UPSTREAM.md`, `UPSTREAM.sha256`,
  `FORK-LICENSE.md`, `CHANGELOG.md`, `FORK-NOTES.md`

`README.upstream.md` is **not** in that list and is not a fork-authored file: it
is a byte copy of upstream's own README, recorded as a copy rather than as a
1300th upstream file. `UPSTREAM.sha256` records `upstream/README.md` alone and
`tools/check-provenance.sh` is what proves the copy has not drifted from the
original.

`flake.lock` is **absent from this tree**, and `devenv.lock` is **absent from
this tree**. `devenv.yaml` pins its nixpkgs revision in source, so there is no
second lock to write and none is invented here; the flake's input is pinned by
revision in `flake.nix` for the same reason. `build.zig.zon`'s `.paths` is the
package's file filter, and the one rule that governs it is that every path it
names must exist: `zig fetch` hashes the named paths, so naming a lock file
while it is absent would fail the fetch rather than record an absence.

### Which of those files carry the SPDX tag, and which do not

Eleven fork-authored files already carried the tag before this notice was
written, and are named here so the inventory is complete rather than sampled:
`build.zig`, `build.zig.zon`, `zig/root.zig`, `tests.zig`, the six files of
`runtime/`, and `tools/check-oracle.sh`. Nine more carry it and were written
with it: `smoke.zig`, `consumer/build.zig`, `consumer/src/main.zig`,
`tools/check-provenance.sh`, `package.nix`, `flake.nix`, `devenv.nix`,
`devenv.yaml` and `.envrc`. Twenty in all, each carrying
`SPDX-License-Identifier: LicenseRef-PublicDomain` on its own first comment
line. That set was read out of the files rather than assumed.

The rest carry the same grant without a tag, and are named here rather than left
for a scanner to read as unlicensed. Five are comment-capable text whose grant is
this inventory and [`FORK-LICENSE.md`](FORK-LICENSE.md):
`zig/translate.h`, `cross-test.profile.sh`, `.github/workflows/verify.yml`,
`.gitignore` and `consumer/build.zig.zon`. The eight documentation and digest
records — this file, `README.md`, `README.zig.md`, `UPSTREAM.md`,
`UPSTREAM.sha256`, `FORK-LICENSE.md`, `CHANGELOG.md` and `FORK-NOTES.md` — are
prose and data with no comment position a tag is expected in, and their grant is
the same public-domain dedication. `README.upstream.md` carries no grant at all
because it is upstream's bytes, not this fork's.

Nothing upstream is affected by any of this: `zig build` installs upstream's own
two licence-bearing files beside the fork's records. `share/licenses/sqlite/`
holds `upstream/LICENSE.md` and `src/sqlite3.h` — the prose dedication and the
per-file blessing — together with `NOTICE.md`, `FORK-LICENSE.md`, `UPSTREAM.md`,
`UPSTREAM.sha256`, `FORK-NOTES.md` and `CHANGELOG.md`: eight files, exactly
`licence_records` in `build.zig:368-377`, which is also what `package.nix`
installs because it runs the same `zig build install`.