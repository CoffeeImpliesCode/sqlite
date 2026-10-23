# Changelog

- Port to Zig 0.17.0.
- Cross-target consumer builds install under the parent prefix instead of invoking third-party runners.
- Added Zig 0.16.0 build support, including WASI handling and the SQLite transient-destructor ABI.
- Added opt-in runtime loading from an absolute path or system-library basename; providers must export every translated entry point.
- Added the typed facade for databases, statements, statuses and columns; `Db.open` returns three outcomes, and `Statement.finalize` consumes its handle by value.
- Added static linkage by default and optional dynamic linkage with upstream's `libsqlite3.so.0` ABI name.
- Bundled SQLite 3.53.4 source and shell with upstream's default compile options.
