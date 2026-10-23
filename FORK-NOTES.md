# Fork notes

## Source deviations

The native files under `src/` are upstream's amalgamation, headers, and shell; this fork adds no C-source patch.

| File | Change and purpose |
|---|---|
| `zig/translate.h` | Adds one aggregate header for translating SQLite's public C declarations into Zig. |
| `zig/root.zig` | Adds typed database and statement wrappers while preserving access to the raw C API. |
| `runtime/loader.zig` | Adds explicit provider loading and single-flight state so callers can choose a shared library. |
| `runtime/library.zig` | Describes SQLite's symbols and validates a provider before publishing it. |
| `runtime/graph.zig` | Connects the loader to Zig's translated declarations for runtime dispatch. |
| `runtime/generate.zig` | Generates target-specific dispatch from the build's translated declarations instead of checked-in bindings. |
| `runtime/sync.c` | Implements the loader's process-wide mutex, condition variable, and thread identity. |
| `runtime/sync.h` | Declares the synchronization interface used by the runtime loader. |
| `tests.zig` | Adds behavioral tests against hand-computed aggregation results and an independent Zig implementation. |
| `smoke.zig` | Adds a small Zig executable that exercises the facade. |
| `consumer/build.zig` | Adds a separate dependent build to exercise package consumption. |
| `consumer/build.zig.zon` | Declares the consumer's local dependency on this package. |
| `consumer/src/main.zig` | Exercises the facade from a downstream module. |
| `tools/check-provenance.sh` | Checks the imported source file set and content against recorded hashes. |
| `tools/check-oracle.sh` | Runs a fixed SQL query through SQLite's shell and compares its output. |
| `tools/fixture/aggregate.sql` | Supplies the query shared by the oracle and its expected-result fixture. |
| `tools/fixture/expected.tsv` | Records the expected output for the SQL oracle. |

## Build graph

- `build.zig` compiles the amalgamation and shell directly. It does not run upstream's configure, autosetup, make, or TCL build system, and it downloads no sources.
- The build defines no `SQLITE_*` macros; upstream's target detection selects the OS and threading implementation. The default build does not enable FTS5, JSON1, math functions, RTREE, or column metadata.
- `-Dsystem=true` or `-fsys=sqlite3` selects an installed SQLite library and the compiler's default system headers; system mode installs neither the bundled library nor shell. The selected headers and library must have compatible declarations and symbols.
- `-Dlinkage` chooses static or shared delivery; `-Druntime` independently selects explicit-provider dispatch. The build generates the dispatch from the selected target's translation rather than linking the bundled archive in runtime mode.
- ELF shared delivery uses soname `libsqlite3.so.0`; Zig's single version field produces `libsqlite3.so.0.53.4` instead of upstream's `libsqlite3.so.3.53.4` filename while preserving the ABI name.
- The build generates relocatable `sqlite3.pc` metadata and installs the library, shell, public headers, and license records. Nix package variants call the same build graph.
- Target-specific links name `-lm`, `-ldl`, and `-lpthread` only where required. The default configuration does not reference zlib or ICU.
- The upstream TCL suite is retained but not built. Its `testfixture` needs canonical test C sources absent from this package, plus TCL 8.6, autosetup, and make. The package's Zig tests and SQL oracle are separate checks, not replacements for that suite.

## Platform boundaries

- WASI is static-only: upstream selects `SQLITE_THREADSAFE=0` and omits loadable extensions. Runtime loading is unavailable there; requesting dynamic linkage for the full matrix reaches WASI, which has no dynamic linker, and fails configuration.
- Runtime loading is also unavailable on Emscripten and freestanding targets. The routed `SQLITE_TRANSIENT` sentinel requires function-pointer alignment of one; linked mode does not have this constraint.
- Windows uses the Windows loader and C runtime, so the build names no separate Unix link libraries. macOS needs `-lm`; `dlopen` and pthread are in libc.
- The generic Unix link rule requests `-ldl` on NetBSD and OpenBSD; availability of that library and need for separate `-lm` or `-lpthread` are not established.
- A runtime provider must export every declaration in the translated header; a system SQLite missing any required symbol is rejected by the loader.
- Zig 0.17 exposes no configure-time runner flags or install-prefix string, so cross-target consumer builds install under the parent prefix.
- Zig 0.17 consumer builds use `--cache-dir <path>` and inherit `ZIG_GLOBAL_CACHE_DIR` and `ZIG_LIB_DIR` from the parent working directory.
