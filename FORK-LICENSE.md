# FORK-LICENSE.md — the grant for this fork's own files

[`NOTICE.md`](NOTICE.md) is the inventory: which files are upstream's, which are
this fork's, and which term covers each. This file is the grant itself, for the
second group only.

## 1. The native source is not covered by anything below

The 4 files under `src/`, the 10 files under `upstream/` and the 1285 files
under `test/` are SQLite's, whole from the `sqlite-amalgamation-3530400.zip` and
`sqlite-src-3530400.zip` release artefacts, and never edited. Their terms are
**public domain** — a dedication, not a licence — and upstream writes it in
prose at `upstream/LICENSE.md` and as a per-file blessing at the head of the
source files (`src/sqlite3.h:1-8`). Nothing in this file re-grants, narrows,
widens or conditions that dedication, and nothing here asserts that SQLite's
authors wrote, reviewed or endorsed a line of fork code.

## 2. The fork-authored material

Everything else in this repository — the Zig build, the typed module and its
tests, the example, the consumer package, the runtime-loading route, the
packaging, the integrity scripts and the documentation — was written for this
fork. The runtime-loading route is the six files under `runtime/`: the reusable
loader, this SDK's descriptor, the build half that wires them together, the
build-time generator, and the two C files that supply the synchronization the
descriptor binds. All six are fork work under this grant; none of them is
upstream material and none is derived from a third-party source.

### Grant

**Those files are released into the public domain**, matching the primary
upstream term of this project, with this dedication:

```
The authors of this file release it into the public domain.  In place of a
legal notice, here is a blessing:

  *   May you do good and not evil.
  *   May you find forgiveness for yourself and forgive others.
  *   May you share freely, never taking more than you give.

To the extent possible under law, the person who associated this work with
this disclaimer has waived all copyright and related or neighboring rights to
this work.  Where a jurisdiction does not permit such a waiver, that person
agrees to release this work under the terms in upstream/LICENSE.md's blessing,
which is the same dedication applied to SQLite itself.
```

That is the same wording upstream applies to its own source, quoted from
`upstream/LICENSE.md` and from the header of every public-domain file in
`src/`. It was chosen so that one term covers this repository end to end: a
consumer of this fork is not left holding a permissive licence beside a
public-domain library and having to work out which obligation applies to which
byte.

### Authority for that grant

The owner of this repository authorized per-project licensing for fork-authored
additions as part of the SDK contract migration, with the term chosen per
project to match that project's primary upstream terms where that is
appropriate. SQLite's primary upstream term is a public-domain dedication
(`upstream/LICENSE.md`), so a public-domain dedication is the choice. The
authorization is recorded here and in `NOTICE.md`; the term above is the owner's,
reached by that authorization and not by any upstream grant.

The owner is not named and no individual copyright holder is invented: the
dedication is deliberately the collective one upstream also uses.

### SPDX identifier

```
LicenseRef-PublicDomain
```

A `LicenseRef-` wrapper, and that is a deliberate distinction rather than a
shortcut. SQLite's term is **not** one of the OSI-approved licences an SPDX
scanner resolves by bare identifier — it is a dedication, not a permission
notice with conditions — so a bare `PublicDomain` would assert a registered
identifier this grant is not, and inventing one would misrepresent the grant.
Every fork-authored file in this tree carries
`SPDX-License-Identifier: LicenseRef-PublicDomain`, which is the accurate
identifier for exactly what is granted: public domain.

Every fork-authored **source, build, packaging and script** file carries that
tag on its own first comment line, named one by one in [`NOTICE.md`](NOTICE.md).
The documentation and digest records do not carry a tag: they are prose and
data, and `NOTICE.md` names each of them explicitly so that a scanner finding no
identifier in `README.md` reads a recorded reason rather than an apparent gap.

### What this does not do

* It does not re-license, sublicense or add a condition to any SQLite file, and
  it does not extend the public-domain dedication upstream made into a claim
  about files upstream ships under a different term — see `NOTICE.md`,
  "Per-file exceptions", for the configure-side files whose term this tree
  cannot state from the files it carries.
* It does not assert that SQLite's authors authored, reviewed, endorsed or are
  affiliated with the fork's files.
* It does not claim a public-domain dedication is the only term the owner could
  have chosen for independently authored work. It is the term chosen, and it
  matches upstream's.

## 3. Material carried but not authored here

There is none. This repository vendors no third-party code, no downloaded
header and no external data file. The 1299 files listed in `UPSTREAM.sha256` are
the complete upstream material, and nothing was added to them.

The two files this build generates are not carried material either, and the
distinction is worth keeping exact rather than dropping a category to make the
sentence short. Under `-Druntime`, `runtime/generate.zig` writes the dispatch
and its patched translation through `Run.addOutputFileArg`, so both land in the
build cache rather than in this tree, and they are built from the translation of
`zig/translate.h` and upstream's own headers that this same build has just
produced for the target being built. A third file is generated on every build
and installed: the relocatable `sqlite3.pc`, written by `build.zig`'s
`add_pkg_config` from `upstream/sqlite3.pc.in`. Nothing is fetched to make any
of them, no third-party code is in them, and none of them is a fork-authored
source file. Every file under `runtime/` in this tree *is* one, under section 2.

## 4. Why a separate file at all

`NOTICE.md` names which fork-authored files carry an `SPDX-License-Identifier`
line and which carry the same grant in prose without one. This file exists so
that the authority, the grant text and the limits of that grant live in one
place, next to the inventory rather than scattered across the files themselves.