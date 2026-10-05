# Changelog

Numbered entries, newest last. Every entry records what changed and why.

**Status vocabulary, used strictly here.** `SOURCE-CONFIRMED` means the claim was
read out of a file in this tree and nothing was executed. `PENDING-VERIFICATION`
means a change has landed and no gate has observed it yet. `OBSERVED` means a
gate ran and its output is named beside the claim. There is no `VERIFIED` entry
in this file, and there is no "passes", "green" or test count anywhere below:
the driver owns every build, test, smoke run and cross-target check, and an
entry that claimed a result nobody observed would be worse than an entry that
admits none exists yet. **Entry 12 is the single exception and is marked
`OBSERVED`** — it reports a gate that was run on request, names the harness
summary and the per-cell logs it was read from, and claims nothing beyond them.

## 1. 2026-10-05 — import of the official SQLite 3.53.4 release artefacts

**Status:** `SOURCE-CONFIRMED` for the import, `PENDING-VERIFICATION` for
everything built from it.

Two release archives were unpacked into this tree and nothing else was fetched:

| Archive | Unpacked into | Files |
|---|---|---:|
| `sqlite-amalgamation-3530400.zip` | `src/` | 4 |
| `sqlite-src-3530400.zip` | `upstream/` and `test/` | 10 + 1285 |

`src/` holds upstream's whole amalgamation — `sqlite3.c` (269 649 lines,
9 515 341 bytes), `sqlite3.h` (14 349 lines), `sqlite3ext.h` (739 lines) and
`shell.c` (37 415 lines). `upstream/` holds the release metadata the build cites
by line: `LICENSE.md`, `README.md`, `VERSION`, `manifest`, `manifest.tags`,
`manifest.uuid`, `auto.def`, `Makefile.in`, `main.mk` and `sqlite3.pc.in`.
`test/` holds upstream's TCL suite whole, including the `fuzzdata*.db` inputs.

No file was edited. `UPSTREAM.sha256` records all 1299 by SHA-256, and
`tools/check-provenance.sh` rejects a missing, extra or renamed file under any of
the three directories.

**Neither archive's own SHA-256 is recorded, because no copy of either archive is
in this tree to hash.** An identifier that was not observed is not one this
repository may state. What is verifiable is every individual file, which is a
strictly finer check. See `UPSTREAM.md`.

## 2. 2026-10-05 — the check-in identity, verified by upstream's own method

**Status:** `SOURCE-CONFIRMED`; recomputed by `tools/check-provenance.sh`.

`upstream/README.md` states the method: the check-in name is the SHA3-256 of
`upstream/manifest` with its trailing `# Remove this line` comment omitted, and
`manifest.uuid` should hold it. Computed over the file as shipped, that gives
`bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`, which is
`upstream/manifest.uuid`, which is `src/sqlite3.h:151`'s `SQLITE_SOURCE_ID`, and
whose first 36 characters are the check-in `src/sqlite3.c:21` names. The
manifest's `D` card, `manifest.tags` and `src/sqlite3.h:152-154` agree on the
date, the tag and the branch.

The per-file half of the same method is partly unexplained and is recorded as
such rather than smoothed over: **869 of the 1285 files under `test/` match the
manifest's SHA3-256 and 416 do not.** Every file under `src/` and `upstream/`
that the manifest names matches (1 of 1 for `src/`, which is `sqlite3ext.h`, and
7 of 10 for `upstream/`, the other three being Fossil's own metadata). The three
generated files `sqlite3.c`, `sqlite3.h` and `shell.c` have no manifest entry by
design — they are `tool/mksqlite3c.tcl` and `tool/mkshellc.tcl` output. The cause
of the 416 is **not established**; the hypotheses tested and rejected are listed
in `FORK-NOTES.md`. Nothing this package compiles or runs is affected.

## 3. 2026-10-05 — the Zig build graph

**Status:** `PENDING-VERIFICATION`.

`build.zig` compiles the two translation units and translates one header. It
defines **no `SQLITE_*` macro on any compile line**, which is the decision the
whole configuration turns on and is stated as SQLite's default rather than as a
list of features. Every platform-dependent fact is read out of `sqlite3.c`'s own
detection and resolved per target in `Platform`: the OS arm, the mutex
selection, the `__wasi__` arm, and the three link libraries each implies
(`-lm -ldl -lpthread` on Unix, `-lm` on Darwin, none on Windows or WASI).

Delivery is `-Dlinkage=static` (default) or `-Dlinkage=dynamic`. The shared
object carries upstream's `libsqlite3.so.0` soname — the ABI name upstream states
at `upstream/main.mk:1516-1519` — and the file name that produces
(`libsqlite3.so.0.53.4`) is recorded where it differs from upstream's own
(`libsqlite3.so.3.53.4`), because one `Compile.version` cannot produce both.

Entry points: `zig build`, `test`, `smoke`, `oracle`, `consumer`, `check`, plus
`cross-test` through `cross-test.profile.sh`. No target is refused: `check` walks
all six baseline rows and reports.

## 4. 2026-10-05 — the typed facade and the tests

**Status:** `PENDING-VERIFICATION`.

`zig/root.zig` publishes `Db`, `Statement`, `Step`, `Status`, `ColumnType` and
`OpenFlags` over the translated `c` module. Three decisions are worth recording
because they are the ones a caller would otherwise have to discover:

* `Db.open` returns a **union**, not an error, because upstream has three
  outcomes and `src/sqlite3.h:3725` returns a live handle even on failure so the
  message can be read through it;
* `Statement.finalize` takes the statement **by value**, so the handle is
  consumed by the call and cannot be finalized twice through the same value;
* the error set is cut at what this module's own code checked, and the library's
  own code is always reachable separately through `errcode`, `extendedErrcode`,
  `errmsg` and `sqlite3_errstr`.

`tests.zig` holds the behavioural proof: a hand-computed twelve-row aggregation,
a second implementation of the same arithmetic in plain Zig, the 64-bit path with
`2^53 + 1`, NULL versus the empty string, embedded NUL bytes in a blob, the
constraint path with its extended code, `sqlite3_close_v2`'s zombie semantics, and
the header-derived status and column-class taxonomies. No test pins a version
string, checks `@hasDecl`, or asserts that a call did not fail.

## 5. 2026-10-05 — the runtime-loading route

**Status:** `PENDING-VERIFICATION`.

Six files under `runtime/`: the reusable `loader.zig`, this SDK's descriptor
`library.zig`, the build half `graph.zig`, the build-time `generate.zig`, and
`sync.c` / `sync.h`. Under `-Druntime=true` the native entry points resolve
through a dispatch table generated from the same translation, written through
`Run.addOutputFileArg` so it lands in the build cache and this directory holds no
generated source.

The provider is named one of exactly two ways — an absolute `path`, or a `system`
basename handed to the platform loader. There is no fallback, no retry after
failure and no replacement of a published provider. A provider must export all
366 declarations of `zig/translate.h`; a partial set is `MissingSymbol`, not a
half-used library. The load-time check exercises the 3-family version, a
`:memory:` open, one step and a 64-bit column read-back, so the scalar width is
tested rather than assumed.

## 6. 2026-10-05 — the upstream-interop fixture

**Status:** `PENDING-VERIFICATION`.

The upstream TCL suite cannot run in this package, and `build.zig` says why at
length rather than fetching a stand-in. What was added instead is a small,
independent interoperability check: `tools/fixture/aggregate.sql` seeds twelve
literal rows and asks for a grouped reduction; `tools/fixture/expected.tsv` holds
the table hand-computed from those rows; `tools/check-oracle.sh` runs the SQL
through **upstream's own shell** (`src/shell.c`) and compares the output byte for
byte. `zig build oracle` installs and then runs that script.

Two front ends, one SQL text, one independently derived answer. It is not a run of
SQLite's test suite and neither `README.md` nor `build.zig` describes it as one.

## 7. 2026-10-05 — the provenance, licence and documentation records

**Status:** `SOURCE-CONFIRMED` for what the records assert about bytes;
`PENDING-VERIFICATION` for everything else.

`UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `FORK-LICENSE.md`,
`tools/check-provenance.sh`, `README.md`, `README.zig.md`, `README.upstream.md`,
`FORK-NOTES.md` and this file.

SQLite's term is a **public-domain dedication**, not a permissive licence, and
`NOTICE.md` states it from the files: the prose at `upstream/LICENSE.md`, the
per-file blessing at `src/sqlite3.h:1-8` and `src/sqlite3ext.h:1-8`, and the
README's own "## Public Domain" section. `NOTICE.md` records the one place where a
single label would be wrong — the three files in `upstream/` whose term this tree
**cannot** state, because the autosetup licence text upstream points at is in a
file neither release archive carries. It is recorded as unknown rather than
guessed. `FORK-LICENSE.md` records the owner-authorised grant for the
fork-authored files, which is the same dedication, so one term covers the whole
repository.

## 8. 2026-10-05 — the standalone Nix and devenv packaging

**Status:** `PENDING-VERIFICATION`.

`package.nix` is the one source-only derivation; `flake.nix` and `devenv.nix`
both call it, so the two entry points cannot describe different packages. It runs
`zig build install` and changes nothing else except the rpath of the ELF files the
build installed, which name a build cache directory that does not exist after
install. `devenv.nix` is the canonical development environment and names eleven
tasks; `cross-test.profile.sh` is settings only and narrows nothing.

Lock files belong to the driver and are absent from this tree on purpose:
`devenv.yaml` pins its nixpkgs revision in source, and `build.zig.zon`'s `.paths`
must not name a path that does not exist, because `zig fetch` hashes the named
paths.

## 9. 2026-10-05 — the consumer package

**Status:** `PENDING-VERIFICATION`.

`consumer/` is a separate package with its own manifest, reached only through a
relative path dependency, so it proves that `dep.module("sqlite3")` resolves from
a package that did not write it. Its program seeds the same twelve rows and
checks a grouped aggregation against a table hand-computed in its own source, and
exits non-zero on any mismatch.

The same source builds against a linked package and a runtime-loaded one;
`sqlite.runtime_loaded` is a comptime constant, so the difference is one branch
and no duplicated program.

## 10. 2026-10-05 — the CI workflow

**Status:** `PENDING-VERIFICATION`.

`.github/workflows/verify.yml` is entirely this fork's: upstream ships no CI with
either release artefact. It runs the provenance gate, the native build, both
linkages, the example, the oracle fixture, a C consumer against the **installed**
tree through pkg-config, the six-target compile-only matrix, and the consumer
package. There is no `continue-on-error` and no matrix row allowed to fail: a row
that is allowed to fail is indistinguishable from a target that was quietly
dropped.

## 11. 2026-10-05 — the Zig 0.16.0 build, made to compile

**Status:** `SOURCE-CONFIRMED` for every change below. The gates were run by the
wave that made these changes; per this file's own rule no result is claimed here.

This tree was authored against Zig 0.16.0's API but had never been compiled. Every
item is a fact the compiler or the C source forced, not a preference.

* **`zig/root.zig`, three `unused capture` errors at the open/close seams.** The
  bodies named a bare `open` where the `if (handle) |live|` capture belonged, so
  the handle passed to `sqlite3_close_v2` was a function, not a pointer. The
  captures are now used and the sentinel-carrying call sites are `transient` and
  `sqlite3_bind_text`/`sqlite3_bind_blob` below.
* **`OpenFlags` could not be a `packed struct(u32)` of eleven `bool`s.** The
  compiler requires the fields' total width to equal the backing integer's. The
  struct now carries the header's own sparse bit positions as explicit widths
  (`reserved_1` … `reserved_4` covering `src/sqlite3.h:606-608`, `:611-617`,
  `:622` and `:626`), so `@bitCast` still produces the `int`
  `sqlite3_open_v2` takes and the test's oracle against the header's own macros
  still holds.
* **`std.meta.intToEnum` is gone from 0.16.0.** `Status.fromCode`,
  `Status.fromExtendedCode` and `ColumnType.fromCode` now call
  `std.enums.fromInt`, which is the function the compiler's own note points at.
* **`SQLITE_TRANSIENT` cannot be a Zig function pointer where function pointers
  are aligned.** `src/sqlite3.h:6429` defines it as
  `(sqlite3_destructor_type)-1`, and `zig build check` failed on `aarch64-linux`,
  `aarch64-macos` and `riscv64-linux` with "pointer type `?*const fn
  (?*anyopaque) callconv(.c) void` requires aligned address". A linked build now
  calls `src/sqlite3.h:5016` and `:5009` through prototypes whose destructor is an
  untyped pointer - the same representation in the ABI - carrying `maxInt(usize)`,
  the all-ones address `-1` widens to. A runtime-loaded build keeps the
  translated call, because there the destructor is a field of the generated table.
* **`sqlite3_bind_blob`'s value parameter is `?*const anyopaque`,** not
  `[*c]const anyopaque`; `[*c]` to an opaque pointee is not a type 0.16.0 accepts.
* **`sqlite3_column_type` returns an optional,** so `columnBlob`'s class check
  reads it directly rather than through `try`.
* **`tools/fixture/expected.tsv` was missing its final newline,** which
  `tools/check-oracle.sh` compares byte for byte and which `wc -l` counted as
  three rows rather than four. The table's contents were already correct.
* **`consumer/build.zig.zon` had no `.fingerprint`,** which 0.16.0 requires; the
  value is the compiler's own suggestion, `0xb7655c6ba16d5c86`.
* **`runtime/library.zig` called a `nullPointer` it never declared,** so
  `zig build consumer -Druntime=true` could not compile. It is defined beside the
  other file-scope constants.
* **`src/shell.c` on `wasm32-wasi`.** Upstream's shell takes `<signal.h>`,
  `<sys/resource.h>`, `getrusage` and `getpid`, and this toolchain's wasi-libc
  answers each with an `#error` naming a switch and a library. `build.zig`'s
  `Platform` now carries that pair for WASI and `add_program` applies both. **No
  upstream file was edited.**

Three claims this tree made about SQLite's behaviour were themselves wrong, and
the behavioural tests are what found them. Each was corrected against the C
source rather than against a passing expectation, and no assertion was removed:

* `sqlite3_step` assigns its answer to the connection on every call
  (`src/sqlite3.c:94581`), so `sqlite3_errcode` answers `SQLITE_ROW` after a row,
  not `SQLITE_OK`. The NULL-column test now asserts that no *error* was recorded.
* A statement stepped after `SQLITE_DONE` is reset and restarted by the library
  (`src/sqlite3.c:94511-94536`), so it answers `SQLITE_ROW` again rather than
  `SQLITE_DONE`. `README.zig.md` carried the same wrong claim and says the
  opposite now.
* `sqlite3_txn_state` reports the btree's own `inTrans`
  (`src/sqlite3.c:84552-84555`), and a deferred `BEGIN` takes no lock until the
  first statement inside it, so the transaction-state test asks after the write.

Two documentation claims did not survive either: `README.zig.md` said `reset()`
keeps bindings in place, and `runtime/library.zig`'s caller could not be
compiled at all.

## 12. 2026-10-05 — the 53-platform matrix, run and recorded

**Status:** `OBSERVED`. Run `20261005-191626-52905-3050`, from this package root,
Zig 0.16.0, `cross-test --jobs 8 --build-jobs 8` over the published 53-platform
Tier 1/2 table, with this tree's own `cross-test.profile.sh` and no target list.
`--jobs 8 --build-jobs 8` overrode the profile's `CROSS_BUILD_JOBS=4`; nothing
else was narrowed.

**Nothing in this tree changed.** This entry and `FORK-NOTES.md` item 9 record a
result; no source, no test, no build graph and no vendored byte was edited.

The harness **exited 1** over `target_count 53`:

| Outcome | Cells |
|---|---|
| pass, `run test sqlite3-tests 25 pass (25 total)` | 20 |
| `build_only`, compiled and never executed | 15 |
| build failure | 18 |
| refused | 0 |
| runtime failure (compiled, then the run failed) | 0 |

Receipt: `$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/sqlite/cross-test-summary.json`
(`exit_code 1`, `counts {pass 20, fail 18, build_only 15, partial 0}`), with one
`build-<target>.log` per cell under
`…/cross/sqlite/runs/20261005-191626-52905-3050/`.

**The 18 failures are all one cause, and it is in this fork's build graph.**
Every NetBSD row and every OpenBSD row stops in `compile lib sqlite3` with

    error: unable to find dynamic system library 'dl' using strategy 'paths_first'. searched paths: none

`Platform.forTarget` sends every Unix that is not Windows, WASI or Darwin
through one arm that sets `.separate_dl = true` (`build.zig:554-561`), which is
what puts `-ldl` on the compile line (`build.zig:857-859`, `build.zig:919-921`)
and in the installed `sqlite3.pc` (`build.zig:1278`). The six FreeBSD rows in
the same run compiled with the same `-ldl`, so that arm is right for FreeBSD
and wrong for NetBSD and OpenBSD. **No fix is applied here** — a correction
owns the edit and the fresh gate after it — and whether `-lm` and `-lpthread`
are also wrong on those two operating systems is not established, because the
build stopped at `-ldl`.

**What this run does not establish.** The 15 `build_only` cells compiled and
were never executed: no Wine and no wasmtime on this host, and no QEMU-user
executor for their operating systems. A `build_only` cell is compile coverage,
never a test pass, and the 20 passing cells are 20 platforms, not 53.
