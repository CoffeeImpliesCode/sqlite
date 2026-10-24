# Zig API

This reference covers the typed facade and its `c` member, the unfiltered translation of public `sqlite3.h` declarations.

## Connections

| API | Contract |
|---|---|
| `Db.open(filename, flags)` | Returns `OpenResult`; `error.NoOpenMode` is its only Zig error. Filename is NUL-terminated UTF-8. |
| `Db.close()` | Calls `sqlite3_close_v2` and clears the handle. Live statements keep the connection as a zombie until finalized. |
| `Db.closeChecked()` | Same close, with `error.CloseFailed` on a non-OK code; the handle is still cleared. |
| `Db.prepare(sql)` | Compiles only the first statement. `PrepareFailed` reports SQLite's failure; `NoStatement` means empty or comment-only SQL. |
| `Db.exec(sql)` | Runs one non-row statement and finalizes it, including on failure. |

`OpenResult` is `.ok(db)`, `.failed { db, code }` (live; read `message()`, then close), or `.no_connection(code)` (no handle). SQLite errors are not Zig errors.

`Db` owns one connection; do not copy it. `close` methods take `*Db` and clear it. Accessors: `errcode()`, `extendedErrcode()`, `errStatus()`, `errmsg()`, `lastInsertRowid()`, `changes()`, `inTransaction()`. `errmsg()` borrows the NUL-terminated message until the next call on that connection.

## Flags, statuses, and errors

`OpenFlags` is packed `u32`; fields default false: `readonly`, `readwrite`, `create`, `uri`, `memory`, `nomutex`, `fullmutex`, `sharedcache`, `privatecache`, `nofollow`, `exrescode`. Open requires `readonly` or `readwrite` plus `create`; `bits()` rejects invalid modes and conflicting mutex/cache flags, so `Db.open` returns `error.NoOpenMode` before calling SQLite.

`Status` maps SQLite primary result codes plus `row` and `done`. `code()` returns the integer; `isOk()` tests `SQLITE_OK`. `fromCode` returns null for unknown values; `fromExtendedCode` extracts the primary code. `ColumnType` maps `.integer`, `.float`, `.text`, `.blob`, `.null`; `code()` returns its integer and `fromCode` returns null for unknown values.

Facade errors: `PrepareFailed`, `NoStatement`, `BindFailed`, `StepFailed`, `NullValue`, `FinalizeFailed`, `CloseFailed`, `NoOpenMode`, `ColumnOutOfRange`. Use `Db.errcode()` or `extendedErrcode()` for SQLite's exact diagnosis; `sqlite.errstr(code)` returns an optional borrowed message.

## Statements

`Statement` owns one prepared handle. Finalize it on every path, commonly with `defer statement.finalize() catch {};`. `finalize()` consumes its value; do not copy a statement and finalize both copies. `sql()` borrows SQL text for the statement's lifetime.

| API | Contract |
|---|---|
| `step()` | Returns `.row` or `.done`; other SQLite codes return `StepFailed`. Row data is valid only for the current row. |
| `runToCompletion()` | Steps a non-row statement to `.done`; a row result is `StepFailed`. |
| `columnCount()` | Number of columns; valid before the first step. |
| `columnName(i)`, `declType(i)`, `columnType(i)` | Zero-based metadata. Name/type may be absent; `columnType` describes the current row, with SQL NULL as `.null`. |
| `columnInt64(i)`, `columnDouble(i)`, `columnText(i)`, `columnBlob(i)` | Zero-based reads; out of range is `ColumnOutOfRange`. Numeric reads use SQLite conversions; text/blob return `NullValue` for SQL NULL or failed conversion. |
| `bindInt64(i, value)`, `bindDouble(i, value)`, `bindNull(i)`, `bindText(i, bytes)`, `bindBlob(i, bytes)` | One-based parameters. Text and blob bytes are copied; explicit text length preserves embedded NUL bytes. |
| `reset()` | Rewinds the statement and clears its bindings. |

Column text/blob data is borrowed until conversion, the next `step`, `reset`, or `finalize`; never free it. Names, declared types, and SQL text are borrowed until finalization. Empty text/blob differs from SQL NULL.

The translated `c.SQLITE_TRANSIENT` macro requires function-pointer alignment of one. On targets with stricter alignment, use `Statement.bindText` and `Statement.bindBlob`; both copy input in linked and runtime-loaded builds.

## Runtime loading

`runtime_loaded` is compile-time constant. In a linked build, `load(source)` is a no-op and `loadedSource()` is null; otherwise call `load` before native calls, and `loadedSource()` is null until success. One provider is selected per module and retained for process lifetime.

`LoadSource` accepts `.path = absolute_path` or `.system = basename_or_soname`; empty, oversized, NUL-containing, relative, and system names with path components are rejected. There is no path-to-name fallback. The same request is idempotent; a different request returns `ProviderMismatch` without replacement.

`LoadError`: `EmptySource`, `SourceTooLong`, `InvalidSource`, `UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ValidationFailed`, `ProviderMismatch`, `ReentrantLoad`. Column-origin metadata (`sqlite3_column_database_name[16]`, `sqlite3_column_table_name[16]`, `sqlite3_column_origin_name[16]`), RTree callbacks, Carray bindings (`sqlite3_carray_bind`, `sqlite3_carray_bind_v2`), unlock-notify, statement scanstatus, snapshot functions, and debug mutex checks (`sqlite3_mutex_held`, `sqlite3_mutex_notheld`) are optional exports. `sqlite3_win32_set_directory`, `sqlite3_win32_set_directory8`, and `sqlite3_win32_set_directory16` are optional outside Windows and required on Windows. All other translated symbols are required; `MissingSymbol` prints the missing export name. Before publication, the loader checks the SQLite 3 ABI family and an in-memory open/prepare/step/integer-read sequence.

After loading, `c.optional_symbols` lists feature- and target-dependent exports; `c.optional(index)` reports availability for a compile-time index. Calling an unavailable optional function panics with its symbol name. These availability APIs exist only in runtime-loaded builds.

## Library information

`libraryVersion()`, `libraryVersionNumber()`, `sourceId()`, and `threadSafe()` report the selected SQLite library. In runtime mode they describe the provider. Text results and `errstr` are borrowed NUL-terminated C strings.
