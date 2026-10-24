// SPDX-License-Identifier: LicenseRef-PublicDomain
// See FORK-LICENSE.md for what that identifier covers.

//! Zig facade for the SQLite 3.53.4 amalgamation, with typed connection and statement helpers.
//! Facade code allocates no Zig memory; slices borrow SQLite-owned memory, which Zig allocators cannot track.
//! Close connections and finalize statements to release SQLite resources.

const std = @import("std");

/// The translated SQLite C API, or its runtime-loaded dispatch.
pub const c = @import("c");

fn isNull(comptime T: type, pointer: T) bool {
    return @intFromPtr(pointer) == 0;
}

// Select loader types from one module per build to preserve nominal type identity.
const rt = @import("rt");

/// True when this module uses a runtime-loaded SQLite dispatch.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Selects a provider by explicit path or system name for `load`.
/// `loadedSource` returns the source that successfully loaded.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Errors returned by `load`.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Loads the selected provider in runtime mode; linked mode is a no-op.
/// Returns `LoadError` on failure; same-source calls are idempotent, and a different provider is rejected after success.
pub fn load(source: LoadSource) LoadError!void {
    if (runtime_loaded) return c.load(source);
}

/// Returns the loaded provider, or null before loading or in linked builds.
/// A successful provider remains loaded for the process lifetime.
pub fn loadedSource() ?LoadSource {
    if (runtime_loaded) return c.loadedSource();
    return null;
}

/// Primary SQLite result codes, including `ROW` and `DONE`; extended codes are not members.
pub const Status = enum(c_int) {
    /// `SQLITE_OK`, `src/sqlite3.h:449`.
    ok = 0,
    /// `SQLITE_ERROR`, `:451`. Generic error.
    error_ = 1,
    /// `SQLITE_INTERNAL`, `:452`. Internal logic error in SQLite.
    internal = 2,
    /// `SQLITE_PERM`, `:453`. Access permission denied.
    perm = 3,
    /// `SQLITE_ABORT`, `:454`. Callback routine requested an abort.
    abort = 4,
    /// `SQLITE_BUSY`, `:455`. The database file is locked.
    busy = 5,
    /// `SQLITE_LOCKED`, `:456`. A table in the database is locked.
    locked = 6,
    /// `SQLITE_NOMEM`, `:457`. A `malloc()` failed.
    nomem = 7,
    /// `SQLITE_READONLY`, `:458`. Attempt to write a readonly database.
    readonly = 8,
    /// `SQLITE_INTERRUPT`, `:459`. Operation terminated by sqlite3_interrupt().
    interrupt = 9,
    /// `SQLITE_IOERR`, `:460`. Some kind of disk I/O error occurred.
    ioerr = 10,
    /// `SQLITE_CORRUPT`, `:461`. The database disk image is malformed.
    corrupt = 11,
    /// `SQLITE_NOTFOUND`, `:462`. Unknown opcode in sqlite3_file_control().
    notfound = 12,
    /// `SQLITE_FULL`, `:463`. Insertion failed because database is full.
    full = 13,
    /// `SQLITE_CANTOPEN`, `:464`. Unable to open the database file.
    cantopen = 14,
    /// `SQLITE_PROTOCOL`, `:465`. Database lock protocol error.
    protocol = 15,
    /// `SQLITE_EMPTY`, `:466`. Internal use only.
    empty = 16,
    /// `SQLITE_SCHEMA`, `:467`. The database schema changed.
    schema = 17,
    /// `SQLITE_TOOBIG`, `:468`. String or BLOB exceeds size limit.
    toobig = 18,
    /// `SQLITE_CONSTRAINT`, `:469`. Abort due to constraint violation.
    constraint = 19,
    /// `SQLITE_MISMATCH`, `:470`. Data type mismatch.
    mismatch = 20,
    /// `SQLITE_MISUSE`, `:471`. Library used incorrectly.
    misuse = 21,
    /// `SQLITE_NOLFS`, `:472`. Uses OS features not supported on host.
    nolfs = 22,
    /// `SQLITE_AUTH`, `:473`. Authorization denied.
    auth = 23,
    /// `SQLITE_FORMAT`, `:474`. Not used.
    format = 24,
    /// `SQLITE_RANGE`, `:475`. 2nd parameter to sqlite3_bind out of range.
    range = 25,
    /// `SQLITE_NOTADB`, `:476`. File opened that is not a database file.
    notadb = 26,
    /// `SQLITE_ROW`, `:479`. `sqlite3_step()` has another row ready.
    row = 100,
    /// `SQLITE_DONE`, `:480`. `sqlite3_step()` has finished executing.
    done = 101,

    /// Returns this status's integer code.
    pub fn code(self: Status) c_int {
        return @backingInt(self);
    }

    /// Returns a matching `Status`, or null when `raw` is not a member.
    pub fn fromCode(raw: c_int) ?Status {
        return std.enums.fromInt(Status, raw);
    }

    /// Returns the status after masking off extended-code bits.
    /// Primary codes pass through unchanged; unknown primary codes return null.
    pub fn fromExtendedCode(raw: c_int) ?Status {
        return std.enums.fromInt(Status, raw & 0xff);
    }

    /// Whether this is `SQLITE_OK`.
    pub fn isOk(self: Status) bool {
        return self == .ok;
    }
};

/// SQLite storage class of a row value, distinct from a column's declared type.
pub const ColumnType = enum(c_int) {
    /// `SQLITE_INTEGER`, `src/sqlite3.h:5356`.
    integer = 1,
    /// `SQLITE_FLOAT`, `:5357`.
    float = 2,
    /// `SQLITE_TEXT`, `:5358`.
    text = 3,
    /// `SQLITE_BLOB`, `:5359`.
    blob = 4,
    /// `SQLITE_NULL`, `:5359`.
    null = 5,

    /// Returns this column class's integer code.
    pub fn code(self: ColumnType) c_int {
        return @backingInt(self);
    }

    /// The class this code names, or null when it is not one of the five.
    pub fn fromCode(raw: c_int) ?ColumnType {
        return std.enums.fromInt(ColumnType, raw);
    }
};

/// Flags for `sqlite3_open_v2`; VFS-only bits are omitted.
/// Requires READONLY or READWRITE with CREATE; `Db.open` rejects other combinations.
pub const OpenFlags = packed struct(u32) {
    /// `SQLITE_OPEN_READONLY`, `src/sqlite3.h:603`. Open read-only.
    readonly: bool = false,
    /// `SQLITE_OPEN_READWRITE`, `:604`. Open for reading and writing.
    readwrite: bool = false,
    /// `SQLITE_OPEN_CREATE`, `:605`. Create the database if it does not exist.
    create: bool = false,
    /// Reserved VFS-only bits; leave zero.
    reserved_1: u3 = 0,
    /// `SQLITE_OPEN_URI`, `:609`. The filename may be a `file:` URI.
    uri: bool = false,
    /// `SQLITE_OPEN_MEMORY`, `:610`. An in-memory database. Needs no path.
    memory: bool = false,
    /// Reserved VFS-only bits; leave zero.
    reserved_2: u7 = 0,
    /// Disable mutexes; use only when one thread uses this connection.
    nomutex: bool = false,
    /// Enable serialized mutexes so threads may share the connection; default except on WASI.
    fullmutex: bool = false,
    /// Use shared cache, overriding the global setting; SQLite discourages it.
    sharedcache: bool = false,
    /// Use a private cache, overriding the global setting.
    privatecache: bool = false,
    /// Reserved VFS-only WAL bit; leave zero.
    reserved_3: u5 = 0,
    /// `SQLITE_OPEN_NOFOLLOW`, `:623`. The filename may not contain a symlink.
    nofollow: bool = false,
    /// Enable extended result codes from the open call.
    exrescode: bool = false,
    /// Reserved bits; leave zero.
    reserved_4: u6 = 0,
    /// Returns the `sqlite3_open_v2` flags, or null for an invalid combination.
    /// Rejects conflicting mutex/cache modes and invalid read/create combinations.
    pub fn bits(self: OpenFlags) ?c_int {
        if (self.nomutex and self.fullmutex) return null;
        if (self.sharedcache and self.privatecache) return null;
        if (!self.readonly and !(self.readwrite and self.create)) return null;
        return @as(c_int, @intCast(@as(u32, @bitCast(self))));
    }
};

/// Errors reported by facade checks and SQLite calls.
pub const Error = error{
    /// Preparing SQL failed; no statement is owned. Inspect `Db.errcode` and `errmsg`.
    PrepareFailed,
    /// SQL prepared successfully but contained no statement.
    NoStatement,
    /// Binding a parameter failed; inspect `Db.errcode` for SQLite's code.
    BindFailed,
    /// Stepping failed; the statement remains owned and must be reset or finalized.
    StepFailed,
    /// A column contains SQL NULL or its conversion failed.
    NullValue,
    /// Finalization failed; SQLite destroys the statement either way.
    FinalizeFailed,
    /// Closing failed; `Db` is cleared either way.
    CloseFailed,
    /// Open flags are invalid; no SQLite call was made.
    NoOpenMode,
    /// A column index is outside the statement's columns.
    ColumnOutOfRange,
};

/// Result of `Statement.step`, distinguishing a row from completion.
pub const Step = union(enum) {
    /// `SQLITE_ROW`: another row is ready and the column accessors are valid.
    row,
    /// The statement finished; column accessors are invalid.
    done,
};

/// Owns one SQLite connection. Do not copy it; `close` clears its handle.
pub const Db = struct {
    /// The handle, or null once `close` has run.
    handle: ?*c.sqlite3,

    /// Opens a UTF-8, NUL-terminated filename; `:memory:` is private in-memory and `""` is temporary on disk.
    /// Returns `OpenResult`; invalid flags yield `error.NoOpenMode`.
    pub fn open(filename: [:0]const u8, flags: OpenFlags) OpenError!OpenResult {
        const bits = flags.bits() orelse return error.NoOpenMode;

        var handle: ?*c.sqlite3 = null;
        const code = c.sqlite3_open_v2(filename, &handle, bits, null);
        if (code == c.SQLITE_OK) {
            if (handle == null) {
                // A null handle has no connection from which to read a diagnostic.
                return .{ .no_connection = code };
            }
            return .{ .ok = .{ .handle = handle } };
        }
        if (handle) |live| {
            // Keep a failed-open connection alive so callers can read `errmsg`.
            return .{ .failed = .{ .db = .{ .handle = live }, .code = code } };
        }
        // With no handle, there is nothing to close or query.
        return .{ .no_connection = code };
    }

    /// Closes with `sqlite3_close_v2`; release is deferred until live statements are finalized.
    /// Clears this value and ignores the result; use `closeChecked` to report failure.
    pub fn close(self: *Db) void {
        if (self.handle) |live| {
            _ = c.sqlite3_close_v2(live);
            self.handle = null;
        }
    }

    /// Closes and clears the connection, returning `error.CloseFailed` on failure.
    pub fn closeChecked(self: *Db) Error!void {
        if (self.handle) |live| {
            const code = c.sqlite3_close_v2(live);
            self.handle = null;
            if (code != c.SQLITE_OK) return error.CloseFailed;
            return;
        }
    }

    /// Compiles the first UTF-8, NUL-terminated SQL statement into an owned `Statement`.
    /// Returns `Error` on failure; empty or comment-only SQL yields `error.NoStatement`.
    pub fn prepare(self: Db, sql: [:0]const u8) Error!Statement {
        var statement: ?*c.sqlite3_stmt = null;
        const code = c.sqlite3_prepare_v2(
            self.handle,
            sql.ptr,
            @intCast(sql.len + 1),
            &statement,
            null,
        );
        if (code != c.SQLITE_OK) return error.PrepareFailed;
        const handle = statement orelse return error.NoStatement;
        return .{ .handle = handle };
    }

    /// Executes SQL that produces no rows, finalizing its statement on all paths.
    /// Returns `Error` on prepare or step failure.
    pub fn exec(self: Db, sql: [:0]const u8) Error!void {
        var statement = try self.prepare(sql);
        defer statement.finalize() catch {};
        _ = statement.runToCompletion() catch |err| return err;
    }

    /// Returns this connection's most recent SQLite result code.
    pub fn errcode(self: Db) c_int {
        return c.sqlite3_errcode(self.handle);
    }

    /// Returns the most recent extended result code, unchanged.
    pub fn extendedErrcode(self: Db) c_int {
        return c.sqlite3_extended_errcode(self.handle);
    }

    /// Returns the primary status of the most recent result code, if recognized.
    pub fn errStatus(self: Db) ?Status {
        return Status.fromExtendedCode(self.errcode());
    }

    /// Returns SQLite's NUL-terminated error message, borrowed until the next connection call.
    /// After `SQLITE_MISUSE`, SQLite may leave the code and message unset.
    pub fn errmsg(self: Db) [:0]const u8 {
        return std.mem.span(c.sqlite3_errmsg(self.handle));
    }

    /// The rowid of the most recent successful insert on this connection.
    pub fn lastInsertRowid(self: Db) i64 {
        return c.sqlite3_last_insert_rowid(self.handle);
    }

    /// Returns the number of rows changed by the most recent statement.
    pub fn changes(self: Db) i64 {
        return @intCast(c.sqlite3_changes(self.handle));
    }

    /// Returns whether the `main` database has a read or write transaction.
    pub fn inTransaction(self: Db) bool {
        return c.sqlite3_txn_state(self.handle, "main") != 0;
    }
};

/// Outcomes of `Db.open`: success, failure with a connection, or failure without one.
pub const OpenResult = union(enum) {
    /// `SQLITE_OK` and a live connection.
    ok: Db,
    /// Failed open with a live connection; read the message and close it.
    failed: struct {
        /// The connection to read the message from, and to close.
        db: Db,
        /// The code `sqlite3_open_v2` returned, unchanged.
        code: c_int,
        /// Returns the failed connection's borrowed SQLite error message.
        pub fn message(self: @This()) [:0]const u8 {
            return self.db.errmsg();
        }
    },
    /// Failed open without a connection; the integer is SQLite's result code.
    no_connection: c_int,
};

/// Error returned before `sqlite3_open_v2` runs.
const OpenError = error{NoOpenMode};

/// Owns one prepared statement; `finalize` consumes this handle.
/// Do not copy it: copies alias the same statement.
pub const Statement = struct {
    /// The prepared statement handle.
    handle: *c.sqlite3_stmt,

    /// Returns the number of columns in the compiled statement.
    pub fn columnCount(self: Statement) usize {
        const count = c.sqlite3_column_count(self.handle);
        return if (count < 0) 0 else @intCast(count);
    }

    /// Returns a borrowed column name, or null past the end.
    /// The name is valid until the statement is finalized.
    pub fn columnName(self: Statement, index: usize) ?[:0]const u8 {
        if (index >= self.columnCount()) return null;
        return std.mem.span(c.sqlite3_column_name(self.handle, @intCast(index)));
    }

    /// Returns the borrowed declared type, or null when the column has no declared type.
    /// Expressions and invalid indexes return null.
    pub fn declType(self: Statement, index: usize) ?[:0]const u8 {
        if (index >= self.columnCount()) return null;
        const declared = c.sqlite3_column_decltype(self.handle, @intCast(index));
        if (isNull(@TypeOf(declared), declared)) return null;
        return std.mem.span(declared);
    }

    /// Returns the current row's storage class, or null for an invalid index.
    /// Call only after `step` returns `.row`.
    pub fn columnType(self: Statement, index: usize) ?ColumnType {
        if (index >= self.columnCount()) return null;
        return ColumnType.fromCode(c.sqlite3_column_type(self.handle, @intCast(index)));
    }

    /// Advances the statement, returning `.row`, `.done`, or `error.StepFailed`.
    /// Row data is valid until the next `step`, `reset`, or `finalize`; reset before reusing after failure.
    pub fn step(self: Statement) Error!Step {
        return switch (c.sqlite3_step(self.handle)) {
            c.SQLITE_ROW => .row,
            c.SQLITE_DONE => .done,
            else => error.StepFailed,
        };
    }

    /// Steps until `.done`; a row result is `error.StepFailed`.
    /// Returns `Error` when stepping fails.
    pub fn runToCompletion(self: Statement) Error!void {
        while (true) {
            switch (try self.step()) {
                .done => return,
                .row => return error.StepFailed,
            }
        }
    }

    /// Reads a 64-bit integer using SQLite's conversion rules.
    /// Returns `error.ColumnOutOfRange` for an invalid index.
    pub fn columnInt64(self: Statement, index: usize) Error!i64 {
        try self.checkColumn(index);
        return c.sqlite3_column_int64(self.handle, @intCast(index));
    }

    /// Reads a floating-point value using SQLite's conversion rules.
    /// Returns `error.ColumnOutOfRange` for an invalid index.
    pub fn columnDouble(self: Statement, index: usize) Error!f64 {
        try self.checkColumn(index);
        return c.sqlite3_column_double(self.handle, @intCast(index));
    }

    /// Returns borrowed UTF-8 bytes (empty text is empty); valid until conversion, step, reset, or finalize.
    /// SQL NULL or conversion failure returns `error.NullValue`; invalid indexes return `error.ColumnOutOfRange`.
    pub fn columnText(self: Statement, index: usize) Error![]const u8 {
        try self.checkColumn(index);
        if (c.sqlite3_column_type(self.handle, @intCast(index)) == c.SQLITE_NULL)
            return error.NullValue;
        const text = c.sqlite3_column_text(self.handle, @intCast(index));
        if (isNull(@TypeOf(text), text)) return error.NullValue;
        const len = c.sqlite3_column_bytes(self.handle, @intCast(index));
        if (len == 0) return "";
        return text[0..@intCast(len)];
    }

    /// Returns borrowed bytes, valid until conversion, step, reset, or finalize; empty BLOBs are empty slices.
    /// Returns `error.ColumnOutOfRange` for invalid indexes and `error.NullValue` for SQL NULL or conversion failure.
    pub fn columnBlob(self: Statement, index: usize) Error![]const u8 {
        try self.checkColumn(index);
        const kind = c.sqlite3_column_type(self.handle, @intCast(index));
        if (kind == c.SQLITE_NULL) return error.NullValue;
        // Reading a BLOB's size does not convert or materialize it; preserve OOM failures for nonempty zeroblobs.
        const blob_len: ?c_int = if (kind == c.SQLITE_BLOB)
            c.sqlite3_column_bytes(self.handle, @intCast(index))
        else
            null;
        if (blob_len) |len| {
            if (len == 0) return "";
        }
        const bytes = c.sqlite3_column_blob(self.handle, @intCast(index));
        if (isNull(@TypeOf(bytes), bytes)) {
            // TEXT-to-BLOB makes no conversion; a missing buffer denotes empty text (src/sqlite3.c:5826).
            if (kind == c.SQLITE_TEXT) return "";
            return error.NullValue;
        }
        const len = blob_len orelse c.sqlite3_column_bytes(self.handle, @intCast(index));
        const raw: [*]const u8 = @ptrCast(bytes);
        return raw[0..@intCast(len)];
    }

    /// Binds a 64-bit integer to a one-based parameter index.
    /// Returns `error.BindFailed` on failure; inspect `Db.errcode` for SQLite's code.
    pub fn bindInt64(self: Statement, index: usize, value: i64) Error!void {
        const code = c.sqlite3_bind_int64(self.handle, @intCast(index), value);
        if (code != c.SQLITE_OK) return error.BindFailed;
    }

    /// Binds a floating-point value to a one-based parameter index.
    /// Returns `error.BindFailed` on SQLite failure.
    pub fn bindDouble(self: Statement, index: usize, value: f64) Error!void {
        const code = c.sqlite3_bind_double(self.handle, @intCast(index), value);
        if (code != c.SQLITE_OK) return error.BindFailed;
    }

    /// Binds SQL NULL to a one-based parameter index.
    /// Returns `error.BindFailed` on SQLite failure.
    pub fn bindNull(self: Statement, index: usize) Error!void {
        const code = c.sqlite3_bind_null(self.handle, @intCast(index));
        if (code != c.SQLITE_OK) return error.BindFailed;
    }

    /// Binds UTF-8 text with an explicit byte length, including embedded NULs.
    /// SQLite copies the bytes; returns `error.BindFailed` on failure.
    pub fn bindText(self: Statement, index: usize, value: []const u8) Error!void {
        const code = if (runtime_loaded)
            c.rtBindTextTransient(
                self.handle,
                @intCast(index),
                @as([*:0]const u8, @ptrCast(value.ptr)),
                @intCast(value.len),
            )
        else
            LinkedBindings.sqlite3_bind_text(
                self.handle,
                @intCast(index),
                @as([*:0]const u8, @ptrCast(value.ptr)),
                @intCast(value.len),
                LinkedBindings.transient,
            );
        if (code != c.SQLITE_OK) return error.BindFailed;
    }

    /// Binds raw bytes with an explicit length.
    /// SQLite copies the bytes; returns `error.BindFailed` on failure.
    pub fn bindBlob(self: Statement, index: usize, value: []const u8) Error!void {
        const code = if (runtime_loaded)
            c.rtBindBlobTransient(
                self.handle,
                @intCast(index),
                @as(*const anyopaque, @ptrCast(value.ptr)),
                @intCast(value.len),
            )
        else
            LinkedBindings.sqlite3_bind_blob(
                self.handle,
                @intCast(index),
                @as(*const anyopaque, @ptrCast(value.ptr)),
                @intCast(value.len),
                LinkedBindings.transient,
            );
        if (code != c.SQLITE_OK) return error.BindFailed;
    }

    /// Clears bindings and rewinds the statement; SQLite return codes are ignored.
    /// For `RETURNING`, inspect `Db.errcode` after stepping for a reset failure.
    pub fn reset(self: Statement) void {
        _ = c.sqlite3_clear_bindings(self.handle);
        _ = c.sqlite3_reset(self.handle);
    }

    /// Destroys the statement and consumes this handle.
    /// Returns `error.FinalizeFailed` if SQLite reports the last evaluation's error.
    pub fn finalize(self: Statement) Error!void {
        if (c.sqlite3_finalize(self.handle) != c.SQLITE_OK) return error.FinalizeFailed;
    }

    /// Returns the SQL text copied during preparation as a borrowed, NUL-terminated slice.
    /// The slice is valid only until the statement is finalized.
    pub fn sql(self: Statement) [:0]const u8 {
        return std.mem.span(c.sqlite3_sql(self.handle));
    }

    /// Reject a column index before it reaches the C call.
    fn checkColumn(self: Statement, index: usize) Error!void {
        if (index >= self.columnCount()) return error.ColumnOutOfRange;
    }
};

// Exclude linked externs from runtime builds, including debug-info relocations.
const LinkedBindings = if (runtime_loaded) struct {} else struct {
    // SQLite's all-ones copy sentinel has no function-pointer alignment requirement.
    const transient: ?*const anyopaque = @ptrFromInt(std.math.maxInt(usize));

    extern fn sqlite3_bind_text(
        statement: ?*c.sqlite3_stmt,
        index: c_int,
        text: [*c]const u8,
        len: c_int,
        destructor: ?*const anyopaque,
    ) c_int;

    extern fn sqlite3_bind_blob(
        statement: ?*c.sqlite3_stmt,
        index: c_int,
        value: ?*const anyopaque,
        len: c_int,
        destructor: ?*const anyopaque,
    ) c_int;
};

/// Returns the provider's NUL-terminated SQLite version string as a borrowed slice.
/// The string remains valid while the provider is loaded.
pub fn libraryVersion() [:0]const u8 {
    return std.mem.span(c.sqlite3_libversion());
}

/// Returns SQLite's version number using its `X * 1000000 + Y * 1000 + Z` encoding.
pub fn libraryVersionNumber() i64 {
    return c.sqlite3_libversion_number();
}

/// Returns the provider's source check-in ID as a borrowed, NUL-terminated slice.
/// The string remains valid while the provider is loaded.
pub fn sourceId() [:0]const u8 {
    return std.mem.span(c.sqlite3_sourceid());
}

/// Returns SQLite's thread-safety mode: 0 single-thread, 1 serialized, or 2 multi-thread.
/// This build reports 0 on WASI and 1 on other targets.
pub fn threadSafe() c_int {
    return c.sqlite3_threadsafe();
}

/// Returns SQLite's English result text as a borrowed slice, or null when no text is available.
/// Accepts primary, extended, or unknown result codes.
pub fn errstr(code: c_int) ?[:0]const u8 {
    const text = c.sqlite3_errstr(code);
    if (isNull(@TypeOf(text), text)) return null;
    return std.mem.span(text);
}
