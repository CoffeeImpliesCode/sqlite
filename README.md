# sqlite3

SQLite 3.53.4, packaged as a Zig SDK with the native library, command-line shell, C headers, and typed Zig facade.
Based on Fossil check-in `bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`; requires Zig 0.16.0.

## Source deviations from upstream

- The SQLite amalgamation, shell, and public headers in `src/` come from the release archives; the native implementation is unchanged. `UPSTREAM.sha256` records the imported files.
- `zig/translate.h` translates the public header. `zig/root.zig` adds a typed facade beside the complete raw C surface. `runtime/` adds explicit runtime loading and generated dispatch; these do not patch SQLite's C implementation.
- The upstream test tree is present but is not built by this package. Its harness also needs canonical test C sources absent from this checkout. A manifest comparison recorded in `FORK-NOTES.md` found 416 of 1,285 `test/` files do not match; the cause is unknown.

## Build deviations

- Zig compiles `src/sqlite3.c` and upstream's `src/shell.c`; the build does not run `configure`, autosetup, make, CMake, or TCL, and it downloads no source.
- The build defines no `SQLITE_*` configuration macros. JSON functions follow SQLite's default (included unless `SQLITE_OMIT_JSON` is set, which this build does not do); FTS5, math functions, RTREE, and column metadata are not enabled.
- The default build delivers `libsqlite3.a`, `sqlite3`, both public headers, a relocatable `sqlite3.pc`, and license/provenance records. `zig build` compiles the example; `zig build test`, `zig build smoke`, `zig build oracle`, and `zig build consumer` are separate steps. `zig build check` compiles its target matrix and does not run it.
- `-Dlinkage=static|dynamic` selects the installed native library; static is the bundled default and system mode defaults to dynamic. On ELF, dynamic delivery uses file name `libsqlite3.so.0.53.4` and soname `libsqlite3.so.0`.
- `-Druntime=true` (default off) routes Zig calls through an explicit provider loader; it is independent of delivered linkage. `-Dsystem=true` (default off, or `-fsys=sqlite3`) selects an installed library instead of the bundled source and does not install this package's library or shell. System headers must be on the compiler's default include path.
- `-Dtarget=<triple>` selects a compile target; `-Doptimize=<mode>` selects the optimization mode. The package manifest has no build dependencies.

## Support matrix

The default `zig build check` graph compiles these targets; this table describes its link configuration, not a guarantee that every target builds on every host.

| Target | Separate link libraries | Boundary |
|---|---|---|
| `x86_64-linux-gnu`, `aarch64-linux-gnu`, `riscv64-linux-gnu` | `-lm -ldl -lpthread` | Generic Unix configuration |
| `aarch64-macos-none` | `-lm` | `dlopen` and pthread are in libc |
| `x86_64-windows-gnu` | None | Uses Windows loader and C runtime |
| `wasm32-wasi` | None | Static only; upstream selects single-thread mode and omits extension loading |

The generic Unix rule also requests `-ldl` on NetBSD and OpenBSD; the recorded Zig 0.16.0 cross-target run could not find that library. Whether those targets need separate `-lm` or `-lpthread` is unknown. Runtime loading is unavailable on WASI, Emscripten, and freestanding targets. Shared delivery needs a dynamic linker; applying `-Dlinkage=dynamic` to the current six-target graph fails when it reaches WASI.

## Consumption

For a local checkout, add the package to a consumer's `build.zig.zon`:

```zig
.dependencies = .{
    .sqlite3 = .{ .path = "../sqlite" },
},
```

The package name, dependency key, Zig module, and C artifact are all `sqlite3`:

```zig
const dep = b.dependency("sqlite3", .{});
const sqlite = dep.module("sqlite3");
const library = dep.artifact("sqlite3");
```

Zig source imports the module as `@import("sqlite3")`; `sqlite.c` exposes the translated public C declarations. The artifact is `libsqlite3.a` by default. C consumers use the installed `sqlite3.pc` and headers, for example `cc app.c $(pkg-config --cflags --libs sqlite3) -o app`; static links use `pkg-config --static --libs sqlite3` to include private libraries.

The SQLite library and this fork's additions use the public-domain dedication; `NOTICE.md` records per-path exceptions.
