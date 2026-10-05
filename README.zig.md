# The Zig interface

Everything a Zig consumer of this package reaches is the module named `sqlite3`.
It has two halves, and they are the same halves upstream's C API has:

* `sqlite.c` — the **translated raw route**. Every declaration in
  `zig/translate.h`, which is exactly `<sqlite3.h>`: 365 functions and the one
  exported data object `sqlite3_version` (`src/sqlite3.h:188`). Nothing is
  hidden and nothing is renamed, so a declaration upstream documents is
  reachable under the name upstream documents.
* the **typed surface** below it — `Db`, `Statement`, `Step`, `Status`,
  `ColumnType`, `OpenFlags`, `load`, `loadedSource` and the four library
  accessors — which owns a handle, keeps the error taxonomy at what its own code
  checked, and says what a rejected parse leaves behind.

The typed half is a convenience over the raw one, not a replacement. Every method
on it is a few lines over a declaration in `c` that a caller can use directly.

## The two routes

### Linked

The default. The library is compiled from `src/sqlite3.c` and linked into the
binary, and every call is a direct call:

```zig
const sqlite = @import("sqlite3");

var db = try sqlite.Db.open(":memory:", .{ .readwrite = true, .create = true });
defer db.close();
try db.exec("CREATE TABLE t(v INTEGER)");

var st = try db.prepare("INSERT INTO t VALUES(?1)");
defer st.finalize() catch {};
try st.bindInt64(1, 9007199254740993); // 2^53 + 1
try st.runToCompletion();
```

### Runtime-loaded

Built with `-Druntime=true`. The library's entry points resolve at run time
through a dispatch table generated from the same translation, and a program must
name a provider before it makes a native call:

```zig
if (comptime sqlite.runtime_loaded) {
    try sqlite.load(.{ .path = try providerPath() });
}
```

Everything below the `if (comptime …)` is one source file in both builds.
`sqlite.runtime_loaded` is a comptime constant, so the branch is not analyzed in
the linked build at all rather than being a runtime branch that costs a
comparison on every call.

The provider is named one of exactly two ways, and there is no third:

| `LoadSource` | meaning | what is refused |
|---|---|---|
| `.{ .path = p }` | an absolute path to a loadable object | a relative path is `InvalidSource`; no search happens |
| `.{ .system = n }` | a basename or SONAME handed to the platform loader | a name containing a path separator is `InvalidSource` |

There is no fallback. A `path` is never retried as a `system` name, a failed
load is not retried against a different file, and a load that has already
succeeded is not replaced — a second request naming something else is
`ProviderMismatch` and changes nothing. One table per configured module, for the
life of the process.

`LoadError` is the whole set of ways a load can decline, and each member is a
condition some code tested: `EmptySource`, `SourceTooLong`, `InvalidSource`,
`UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ValidationFailed`,
`ProviderMismatch`, and one more for a load re-entered from inside itself.

### What `c` carries beyond the declarations

`c` is not a filtered namespace. It is the translation of the whole public
header, so:

* `sqlite3_compileoption_used` and `sqlite3_compileoption_get` are there, which
  is how a caller asks what this build actually compiled in rather than trusting
  a claim in a README. This build defines no `SQLITE_*` option, so both answer
  zero until a caller changes that.
* `sqlite3_limit`, `sqlite3_config`, `sqlite3_db_config`, the whole `sqlite3_vfs`
  and `sqlite3_module` families and the `sqlite3_*_hook` set are reachable.
  Nothing is behind a facade gate.
* `sqlite3_version` is the header's own data object, and reading it is reading
  the provider's memory, not a copy this module keeps.
* The `sqlite3_int64` typedef is the header's own: `long long int` on the
  ordinary path (`src/sqlite3.h:304-307`). A provider compiled with
  `SQLITE_OMIT_FLOATING_POINT` substitutes `__int64` (`src/sqlite3.h:314-316`)
  and is a different ABI under the same names — which is why the loader's
  load-time check exercises `sqlite3_column_int64` rather than trusting the
  version number alone.

## The typed surface

### Loading and lifecycle

| | |
|---|---|
| `sqlite.load(source: LoadSource) LoadError!void` | resolve and publish one provider |
| `sqlite.loadedSource() ?LoadSource` | what was published, or null |
| `Db.open(filename, flags) OpenError!OpenResult` | three outcomes, not one |
| `Db.close()` / `Db.closeChecked()` | unconditional, or `CloseFailed` |
| `Db.exec(sql)`, `Db.prepare(sql)` | the two ways to run text |
| `Db.errcode()`, `Db.extendedErrcode()`, `Db.errStatus()`, `Db.errmsg()` | the library's own diagnosis |
| `Db.lastInsertRowid()`, `Db.changes()`, `Db.inTransaction()` | the connection's state |
| `sqlite.libraryVersion()`, `.libraryVersionNumber()`, `.sourceId()`, `.threadSafe()`, `sqlite.errstr(code)` | the library describing itself |

`Db.open` returns a union, because upstream has three outcomes and collapsing
them would discard one:

```zig
switch (sqlite.Db.open(":memory:", .{ .readwrite = true, .create = true })) {
    .ok => |db| { /* use it, and close it */ },
    .failed => |f| {
        // Upstream returns a live handle even on failure (src/sqlite3.h:3725),
        // because the message has to be read through it. It is given back, not
        // closed, so the string stays readable; the caller must still close it.
        std.debug.print("{s} ({d})\n", .{ f.message(), f.code });
    },
    .no_connection => |code| { /* nothing was opened */ },
}
```

### Constants and types

`OpenFlags` is a `packed struct(u32)` whose every field defaults to `false`, so
`.{ .readwrite = true, .create = true }` and a partial literal both mean exactly
what they say. `bits()` returns `null` for the two combinations
`src/sqlite3.h:3777-3788` says conflict — `nomutex` with `fullmutex`, and
`sharedcache` with `privatecache` — and for a mode that is neither read-only nor
read-write-and-create, per `src/sqlite3.h:3741-3744`. `Db.open` turns that null
into `error.NoOpenMode` rather than passing a combination upstream calls
undefined.

`Status` and `ColumnType` are `enum(c_int)` over the header's own values, with
`code()`, `fromCode()` and `fromExtendedCode()`. A code outside the set is a
`null` from `fromCode` rather than a cast to a wrong member.

`Step` is a two-member union: `.row` and `.done`. `.done` is terminal for that
execution and the column accessors are not valid after it. A statement stepped
again after `.done` is reset and restarted by SQLite itself
(`src/sqlite3.c:94511-94536`), so a row-producing statement answers `.row`
again rather than `.done`; `Statement.reset` is what rewinds one deliberately,
and clears the bindings with it.

### A statement

`Statement` owns one `sqlite3_stmt`. `finalize` takes it **by value**, so the
handle is consumed by the call and cannot be finalized twice through the same
value — which is what makes `defer statement.finalize() catch {}` safe and what
makes a copied `Statement` a bug rather than a second owner.

```zig
var st = try db.prepare(
    \\SELECT account, SUM(cents), COUNT(*), MIN(entry), MAX(entry)
    \\  FROM ledger
    \\ GROUP BY account
    \\ ORDER BY account
);
defer st.finalize() catch {};

try std.testing.expectEqual(@as(usize, 5), st.columnCount());
try std.testing.expectEqualStrings("SUM(cents)", st.columnName(1).?);
try std.testing.expect(st.declType(1) == null); // no table behind this column

while (true) {
    switch (try st.step()) {
        .done => break,
        .row => {
            const name = try st.columnText(0);
            const sum = try st.columnInt64(1);
            // ...
        },
    }
}
```

Reading a column is where the NULL question has to be answered honestly, because
SQLite has five storage classes and one of them is not a value a narrower
function can express:

| call | `SQLITE_NULL` | why |
|---|---|---|
| `columnInt64(i)` | `error.NullValue` | no integer exists; a zero would be a lie |
| `columnDouble(i)` | `error.NullValue` | same |
| `columnText(i)` | `error.NullValue` | same |
| `columnBlob(i)` | `error.NullValue` | same |
| `columnType(i)` | `.null` | the class is the answer here, not a failure |

An empty string and a NULL are different answers to different calls:
`columnText` on `''` returns the empty slice; on NULL it is `error.NullValue`.
Binds have the same split: `bindNull(1)` writes a SQL NULL, and `bindText(1, "")`
writes the empty string. `bindText` and `bindBlob` copy, and say so —
`src/sqlite3.h` passes `SQLITE_TRANSIENT` (`src/sqlite3.c` documents that as
"the database makes its own private copy"), so the caller's buffer may go out of
scope immediately afterwards.

`reset()` returns a statement to its start **and clears its bindings**, because
`src/sqlite3.h:4993` says a reset does not clear them and `:4994` says an unbound
parameter reads as NULL - so the shape this module's own tests use is `reset` /
`bind` / `runToCompletion` per row, with every parameter bound afresh, and a
reset that left the previous row's values behind would read them here.

### What an out-of-range index does

It is `error.ColumnOutOfRange`, checked against `columnCount()` before the C
call. `src/sqlite3.h:5116` gives `sqlite3_column_count`, and a column accessor
given an index it does not have is undefined behaviour in C; an ordinary
comparison in Zig is a better contract than a `std.debug.assert`, because an
assertion disappears in ReleaseFast and this one does not.

### The error taxonomy, and where it stops

`Error` is cut at what this module's own code checked. `PrepareFailed` is
"prepare returned something other than `SQLITE_OK`", not a list of every reason
SQLite might refuse SQL — upstream publishes a taxonomy of about a hundred
result codes (`sqlite3_errstr`), and a Zig error set with a hundred members
would be an upper bound that says nothing about which one this code can hit.

The library's own answer is never discarded: `Db.errcode()` and
`Db.extendedErrcode()` return the exact code, `sqlite3_errstr` turns it into a
sentence, and `db.errmsg()` gives the connection's own message. An error name
tells a caller which branch of *this* code failed; the code tells them what
SQLite thought.

## Ownership rules a caller must respect

These are not style advice; each one is a use-after-free if broken, and no test
framework here can supply a leak oracle for memory SQLite's own allocator owns.

1. **One owner per `Db`.** `Db` is a value holding one optional pointer. Copying
   it gives two owners of one `sqlite3` object. Every method takes it by value
   and nothing hands out a second owning copy.
2. **`close` clears the handle.** It takes `*Db` and nulls the field, so a
   second `close` is a no-op rather than a double free, and a closed connection
   cannot be reached through the same value again.
3. **`sqlite3_close_v2` semantics are preserved.** A connection with a live
   statement closes as "zombie": the statement is destroyed, the connection
   memory is released when the last statement is. That is upstream's own
   contract (`src/sqlite3.h:335-343`), and `tests.zig` exercises it rather than
   working around it.
4. **Finalize every statement, on the error path too.** `defer … catch {}` is
   the shape; the `catch` is there because `finalize` can report a code and a
   `defer` cannot return one.
5. **`exec` leaves no live statement.** It prepares, steps to completion and
   finalizes inside the call, including when the statement fails, so a caller
   that used it cannot leak one.
6. **Memory inside SQLite is SQLite's.** `sqlite3_malloc64` and `sqlite3_free`
   hand out and take back memory from whatever allocator the library was built
   with. No Zig allocator is in that path and no leak oracle can see it. The
   largest single thing that allocator does is create and drop a connection, and
   that is what the tests do.

## The runtime route

### What a provider must be

All 366 declarations of `zig/translate.h`: the 365 functions and
`sqlite3_version`. This build defines no `SQLITE_*` option, so the optional list
is empty and the excluded list is empty: a provider that does not export the
whole default-build symbol set is **refused**, not half used. The answer to a
missing name is `MissingSymbol`.

The load-time check, before anything is published:

* `sqlite3_libversion_number` is in the 3 family — the ABI *family* check, not
  an exact version, because `src/sqlite3.h:130-136` says `SQLITE_VERSION_NUMBER`
  is always larger than the release it derives from, which is what makes the
  major component the stable part and a point release an addition;
* a `:memory:` database opens, a statement prepares, one step returns
  `SQLITE_ROW`, and a column reads back as the integer 1 — through the
  provider's own code and its own allocator, which exercises the tokenizer, the
  b-tree, the in-memory VFS and the 64-bit column path;
* `sqlite3_libversion` and `sqlite3_sourceid` are read *out of* the provider, not
  compared against this build's constants, so a 3.40 provider stays usable and
  the caller can see which one it got.

`sqlite3_initialize` and `sqlite3_shutdown` are not called. They are
process-global (`src/sqlite3.h:1689-1690`) and the loader does not own the
provider's global state; `sqlite3_open_v2` calls `sqlite3_initialize` itself
unless `SQLITE_OMIT_AUTOINIT` is defined, which this build does not define
(the WASI arm of that is `src/sqlite3.c:16571`).

### What is not claimed

A provider whose calling convention for the varargs and function-pointer
families differs would pass every check above and still be a different ABI.
`sqlite3_config`, `sqlite3_db_config`, `sqlite3_bind_text` through
`sqlite3_bind_blob`, the `sqlite3_vfs` and `sqlite3_module` structures and the
`sqlite3_*_hook` set all cross that boundary as function pointers and varargs.
Nothing here claims more than the checks actually exercise.

### The exported surface

`runtime/library.zig` is this SDK's descriptor and the only file another SDK
replaces. It names the synchronization binding
(`sqlite_rt_lock`, `sqlite_rt_unlock`, `sqlite_rt_wait`, `sqlite_rt_broadcast`,
`sqlite_rt_thread_self` — `runtime/sync.c` compiled with
`RT_SYNC_PREFIX=sqlite_rt`, which `runtime/graph.zig` passes), the
`library_name` the platform loader is given for a `.system` request, and the
checks above. `runtime/loader.zig` holds no per-SDK name at all, which is what
lets two SDKs — or two configurations of one — hold their own loader state in
one process without sharing any of it.

## What the tests cover

`tests.zig` is the behavioural proof; `smoke.zig` is an example and proves
nothing on its own.

| Proof | What it is |
|---|---|
| **Independent known answer** | the twelve-row ledger in `tools/fixture/aggregate.sql`, whose grouped answer is hand-computed: `a` 425 over 5, `b` 575 over 4, `c` −575 over 3, whole table 425 over 12 |
| **Second implementation** | `reduce` computes the same five numbers from the same twelve rows in ordinary Zig, with no SQL; both are asserted against the hand-written table, so a disagreement is the SQL engine's |
| **Upstream interop** | `zig build oracle` runs the *same SQL text* through upstream's own shell (`src/shell.c`) and compares with the same expected table, byte for byte — two front ends, one question |
| **Behavioural boundaries** | `2^53 + 1` through a bind and an aggregate; NULL versus `''`; embedded NUL bytes in a blob; a primary-key violation as `SQLITE_CONSTRAINT` with its extended code; a syntax error with the library's diagnosis; an out-of-range column index; an undefined open-flag combination refused before the library is touched; a failed open that still returns a describable connection; `close` twice; a connection closed with a live statement; a reset statement reusable; `last_insert_rowid` and `changes`; `close_v2`'s zombie semantics; a failed `exec` leaving nothing live |
| **Header-derived taxonomy** | every `Status` member against the header's value, all five `ColumnType` classes reachable from one table, `errstr` for a known and an unknown code |

What is deliberately absent: no test pins a version string, no test checks
`@hasDecl` or export presence, and no test asserts that a call did not fail. The
version macros are the provenance record's business, and the one place a version
matters behaviourally is the 64-bit integer path, which is exercised as
arithmetic rather than as a string comparison.

`tools/check-provenance.sh` checks that the SQL in `tools/fixture/aggregate.sql`
and the SQL `tests.zig` runs cannot drift apart, and that the twelve seeded rows
appear in both files as the same literals.
