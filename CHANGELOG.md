# Changelog

- Read empty BLOBs and text as empty slices without consulting stale connection errors; preserve SQL NULL and conversion-failure errors.
- Exclude linked-only text/blob bind declarations from runtime dispatch, avoiding unresolved native symbols in debug consumers while retaining the C sentinel adapter.
- Fix runtime-loaded text/blob binds on AArch64 and RISC-V with a C sentinel adapter; add copy/empty-binding consumer checks and keep the static-musl provider consumer compile-only.
- Accept providers without optional Carray bindings, check their absence in the bundled-provider consumer, and name missing required exports in loader diagnostics.
- Accept absent Win32 directory exports outside Windows and preserve environment-only provider selection through cached nested consumer builds.
- Accept SQLite providers without opt-in column metadata, RTree, unlock-notify, scanstatus, snapshot, or debug mutex exports; add a bundled shared-provider consumer regression to `test`.
- Omit loaderless targets from shared and runtime-loading check matrices without changing the requested target's linkage.
- Port to Zig 0.17.0.
- Cross-target consumer builds install under the parent prefix instead of invoking third-party runners.
- Added Zig 0.16.0 build support, including WASI handling and the SQLite transient-destructor ABI.
- Added opt-in runtime loading from an absolute path or system-library basename; providers must export every translated entry point.
- Added the typed facade for databases, statements, statuses and columns; `Db.open` returns three outcomes, and `Statement.finalize` consumes its handle by value.
- Added static linkage by default and optional dynamic linkage with upstream's `libsqlite3.so.0` ABI name.
- Bundled SQLite 3.53.4 source and shell with upstream's default compile options.
