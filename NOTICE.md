# Notice

SQLite's source is dedicated to the public domain. `upstream/LICENSE.md` contains the dedication and affidavit note. The per-file blessing appears in `src/sqlite3.h` and `src/sqlite3ext.h`, and in the amalgamated sources `src/sqlite3.c` and `src/shell.c`.

## Upstream scope

`upstream/LICENSE.md` states that the dedication covers:

- primary SQLite source files under `src/`;
- test cases and testing code under `test/`;
- extension source and tests under `ext/` (not vendored here);
- code in the generated `sqlite3.c` and `sqlite3.h`, the command-line interface, and utility programs.

The generated files `src/sqlite3.c`, `src/sqlite3.h`, `src/sqlite3ext.h`, and `src/shell.c`, and all files under `test/`, are within that grant. `upstream/README.md` states the public-domain term as well.

The blessing quoted in `upstream/LICENSE.md` is:

> The author disclaims copyright to this source code.  In place of a legal
> notice, here is a blessing:
>
>   *   May you do good and not evil.
>   *   May you find forgiveness for yourself and forgive others.
>   *   May you share freely, never taking more than you give.

`upstream/LICENSE.md` describes autosetup and legacy autoconf material as BSD-style. The referenced `autosetup/LICENSE` is absent from both imported archives, so the exact terms for `upstream/auto.def`, `upstream/Makefile.in`, and `upstream/main.mk` are unknown. These files are not build inputs. `upstream/sqlite3.pc.in` has no term stated in the file and is used as a template. Upstream says non-public-domain configuration code does not reach SQLite build products; attribution is not required to use SQLite itself, but may be required to republish the configure and build scripts.

| Paths | Term |
|---|---|
| `src/sqlite3.c`, `src/sqlite3.h`, `src/sqlite3ext.h`, `src/shell.c`, `test/` | SQLite public-domain dedication |
| `upstream/LICENSE.md`, `upstream/README.md`, `upstream/VERSION`, `upstream/manifest`, `upstream/manifest.tags`, `upstream/manifest.uuid` | Public domain |
| `upstream/auto.def`, `upstream/Makefile.in`, `upstream/main.mk` | Exact term unknown; see missing autosetup licence above |
| `upstream/sqlite3.pc.in` | No term stated in the file |
| Fork-authored paths listed below | Public domain under `FORK-LICENSE.md` |

## Fork-authored scope

The following files were written for this fork and are released under the grant in `FORK-LICENSE.md`:

| Group | Paths |
|---|---|
| Build | `build.zig`, `build.zig.zon`, `.gitignore`, `cross-test.profile.sh`, `zig/root.zig`, `zig/translate.h` |
| Facade and consumer | `tests.zig`, `smoke.zig`, `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig` |
| Runtime | `runtime/loader.zig`, `runtime/library.zig`, `runtime/graph.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h` |
| Packaging | `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc` |
| Tools and fixtures | `tools/check-provenance.sh`, `tools/check-oracle.sh`, `tools/fixture/aggregate.sql`, `tools/fixture/expected.tsv` |
| Records | `README.md`, `README.zig.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `FORK-NOTES.md`, `NOTICE.md`, `FORK-LICENSE.md`, `CHANGELOG.md` |

`README.upstream.md` is a byte copy of `upstream/README.md`, not fork-authored; `tools/check-provenance.sh` compares the two. The package installs `upstream/LICENSE.md`, `src/sqlite3.h`, `NOTICE.md`, `FORK-LICENSE.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `FORK-NOTES.md`, and `CHANGELOG.md` under `share/licenses/sqlite/`.
