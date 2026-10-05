// SPDX-License-Identifier: LicenseRef-PublicDomain
// See FORK-LICENSE.md for what that identifier covers.

//! Zig facade over the SQLite 3.53.4 amalgamation.
//!
//! No part of SQL is reimplemented here. Every value that comes back out of this
//! module was produced by the C under `src/`, reached through `pub const c`,
//! the module the translation step produces from `zig/translate.h`. What the
//! facade adds is the part a C header cannot express: a connection that owns
//! itself and says what closing it means, columns named by index with their
//! types made explicit, borrowed bytes handed back as slices with the lifetime
//! written down, and one honest answer for each way the C API can refuse.
//!
//! ## Import routes
//!
//! One Zig route is published: `dep.module("sqlite")` in the dependent's
//! `build.zig`, which is `@import("sqlite")` in source. The translated headers
//! are `c` on that same module and are not published as a module of their own,
//! so the declarations and the library that satisfies them arrive through one
//! route. A C consumer takes the installed headers and the installed library
//! instead; `README.zig.md` names that layout.
//!
//! ```zig
//! const sqlite = @import("sqlite");
//! const std = @import("std");
//!
//! pub fn main() !void {
//!     const opened = sqlite.Db.open(":memory:", .{});
//!     var db = switch (opened) {
//!         .ok => |d| d,
//!         .failed => |f| {
//!             std.debug.print("sqlite: {s} ({d})\n", .{ f.message, f.code });
//!             return error.OpenFailed;
//!         },
//!         .no_connection => |code| return error.OutOfMemory,
//!     };
//!     defer db.close();
//!
//!     try db.exec("CREATE TABLE t(a INTEGER, b TEXT)");
//!     var st = try db.prepare("INSERT INTO t VALUES (?1, ?2)");
//!     defer st.finalize() catch {};
//!     try st.bindInt64(1, 42);
//!     try st.bindText(2, "answer");
//!     _ = try st.runToCompletion();
//! }
//! ```
//!
//! ## Allocation
//!
//! This module allocates nothing and wraps nothing on the heap. `Db` is one
//! optional pointer, `Statement` is one pointer, and every string a getter
//! returns is a borrowed slice into memory the C library already owns.
//!
//! That ownership is upstream's, and it is worth stating plainly: the allocator
//! is the one SQLite was compiled with, reached through `sqlite3_malloc64`
//! (`src/sqlite3.h:3319`) and `sqlite3_free` (`src/sqlite3.h:3322`). Nothing
//! here can bound, intercept or account for those allocations, and a Zig test
//! allocator cannot be given a leak oracle for memory a third-party allocator
//! owns. `Db.close` closes the connection, which releases all of it; that is the
//! whole answer this module can give.
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which
//! at comptime.
//!
//! *Linked* is the default. The amalgamation is linked, `c` is the translation
//! of `<sqlite3.h>`, and every call below is a direct call with no table and no
//! check.
//!
//! *Runtime-loaded* is `-Druntime=true`. `c` is a generated dispatch, every
//! native entry point is reached through one process-lifetime table, and
//! nothing is linked into this module at all. A call before the table is filled
//! is an ordinary panic naming the function, in every optimization mode, and
//! `load(source)` is the only thing that fills it: an explicit path or an
//! explicit system name, no fallback between them, atomic publication once every
//! symbol resolved and the library's own check passed, and an explicit retry
//! that a later caller may ask for.
//!
//! Both configurations expose the same names and the same types. Everything that
//! differs is a comptime branch on `runtime_loaded`, so a build resolves only
//! the route it has and a reader of one route is reading the one that will run.
//! `c` is the translation itself in the linked case and the dispatch in the
//! other, which is why a facade and the dispatch share one nominal type per
//! declaration rather than two.
//!
//! ## What a rejection leaves behind
//!
//! Every fallible function here is total: it either succeeds, or returns an
//! error and leaves the object it was called on in a state the header defines.
//!
//!   * `Db.open` returns a union rather than an error, because upstream has two
//!     distinct failures and one Zig error cannot carry both: `sqlite3_open_v2`
//!     hands back a connection even when it fails, so that the message can be
//!     read (`src/sqlite3.h:3719-3726`), and the one documented exception is a
//!     NULL connection when SQLite cannot allocate one. `.failed` keeps the
//!     connection so `errmsg` can still be read from it - closing it here would
//!     destroy the only diagnosis there is - and `.no_connection` is that NULL.
//!   * `Db.prepare` never leaves a half-built statement. On any error `ppStmt` is
//!     NULL (`src/sqlite3.h:4540`) and nothing is owned; on `SQLITE_OK` with a
//!     NULL `ppStmt` the input compiled to no statement at all - an empty
//!     string or a comment (`src/sqlite3.h:4541-4542`) - which is
//!     `error.NoStatement`, not a failure of the database.
//!   * `Statement.finalize` takes the statement by value, so the handle is
//!     consumed and cannot be finalized twice through the same value. It
//!     returns the most recent evaluation's code (`src/sqlite3.h:5595-5600`),
//!     which is upstream's own report and not this module's judgement.
//!   * `Statement.step` is the only place a row can come into existence, and it
//!     answers `SQLITE_ROW`, `SQLITE_DONE` or an error - the three things
//!     `sqlite3_step` can return (`src/sqlite3.h:479-480`).
//!   * `Db.close` takes `*Db` and clears it, so a closed connection cannot be
//!     used through the same value afterwards.
//!
//! ## What this module does not wrap
//!
//! The rest of the 365 declarations the header makes is reachable through `c`
//! and is deliberately not given a name here. `sqlite3_backup`, the `sqlite3_vfs`
//! and `sqlite3_module` registration interfaces, the session extension's
//! virtual-table surface, `sqlite3_str_*`, the `sqlite3_carray_*` array-binding
//! family and the tracing, authorization and user-data setters are all one
//! direct call away, with the header's own types. Wrapping them would mean
//! re-deriving ownership rules this module would then have to defend, for
//! interfaces none of this package's own tests exercise. What is wrapped here is
//! the part the C header itself spells out as a lifecycle - open, prepare, step,
//! column, finalize - plus the parameter binding without which none of those
//! five can be used on real data.

const std = @import("std");

// The translated `<sqlite3.h>`, or the generated dispatch over it when
// `-Druntime=true`. One nominal type per declaration either way.
pub const c = @import("c");

/// Whether a translated pointer is null.
///
/// A C pointer arrives in Zig carrying no null in its type, and that is not an
/// oversight in the translation but what C says: `sqlite3_column_text` is
/// declared `const unsigned char *` (`src/sqlite3.h:5584`), and the header is
/// the only place that says a null is possible - `src/sqlite3.h:5573-5578`
/// names two situations in which it is. So the null is an address here, and
/// `@intFromPtr` is what compares one without inventing an optional pointer the
/// translation did not produce.
///
/// `T` is the pointer type itself, so this works for a sentinel-terminated
/// `const char *` and for a `const void *` alike without the caller having to
/// spell the type.
fn isNull(comptime T: type, pointer: T) bool {
    return @intFromPtr(pointer) == 0;
}

// The loader core, for the *linked* configuration only.
//
// In a runtime-loaded build the dispatch creates the one core instance and
// re-exports `LoadSource`/`LoadError` from it, so importing it here as well
// would be a second, nominally distinct `LoadSource` - and `load` below would be
// handing the facade's type to a function expecting the dispatch's. One instance
// per build, and the comptime branch below picks which module it comes from.
const rt = @import("rt");

/// True in this build, and not a test the driver runs.
///
/// A dispatch declares it (`runtime/generate.zig` writes `rt_runtime_loaded`
/// into the generated file); a plain translation does not, so a linked build
/// answers false without naming its configuration twice.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open, or an answer from a load attempt.
///
/// One type in both configurations, for the reason the module comment gives.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline, or none.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Name a provider and fill the dispatch.
///
/// The only way the table becomes usable, in a runtime-loaded build. A linked
/// build has no table, so this is a no-op that exists so that one program can
/// name a provider and work in both configurations; `loadedSource` then answers
/// null, because nothing was loaded - there is nothing it could have loaded.
///
/// The call is explicit in both directions: a `.path` names a file and a
/// `.system` names what the platform loader searches for, and one is never
/// silently turned into the other. Calling it twice with the same source is
/// idempotent; calling it with a different source after one has succeeded is
/// `error.ProviderMismatch` and changes nothing.
pub fn load(source: LoadSource) LoadError!void {
    if (runtime_loaded) return c.load(source);
}

/// The provider already loaded, or null.
///
/// Null in a linked build and after no load. A non-null answer is the request
/// that succeeded, retained for the life of the process.
pub fn loadedSource() ?LoadSource {
    if (runtime_loaded) return c.loadedSource();
    return null;
}

/// A primary SQLite result code.
///
/// The twenty-seven values are `src/sqlite3.h:449-476` transcribed, name for
/// name and value for value; `src/sqlite3.h:478-480` adds the two
/// `sqlite3_step` outcomes `SQLITE_ROW` and `SQLITE_DONE`. This is a
/// transcription of the header's own taxonomy, not a second definition of it:
/// nothing here computes a code, and `code` is the number upstream returned.
///
/// Extended result codes - `SQLITE_CONSTRAINT_CHECK` and its siblings,
/// `src/sqlite3.h:502-620` - are *not* members. They are the primary code with
/// bits in the high byte (`src/sqlite3.h:500`: `SQLITE_ERROR | (1<<8)`), and a
/// facade that folded them into these fields would lose the primary code.
/// `Db.extendedErrcode` returns one unchanged, and `Status.fromExtendedCode`
/// takes the primary part of one.
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

    /// The number upstream returned, for any code including an extended one.
    pub fn code(self: Status) c_int {
        return @intFromEnum(self);
    }

    /// The primary code, or null when `raw` is not one this build knows.
    ///
    /// An extended code is *not* a member and answers null, which is the honest
    /// answer: `SQLITE_CONSTRAINT_CHECK` is not a different kind of thing from
    /// `SQLITE_CONSTRAINT`, and folding it in would hide which one it was. Use
    /// `fromExtendedCode` for that.
    pub fn fromCode(raw: c_int) ?Status {
        return std.enums.fromInt(Status, raw);
    }

    /// The primary part of an extended result code.
    ///
    /// `src/sqlite3.h:500` defines every extended code as `PRIMARY | (N<<8)`,
    /// so the primary code is what remains after masking off the high byte.
    /// A primary code passes through unchanged, which is what makes this usable on
    /// `sqlite3_errcode` as well as on `sqlite3_extended_errcode`.
    pub fn fromExtendedCode(raw: c_int) ?Status {
        return std.enums.fromInt(Status, raw & 0xff);
    }

    /// Whether this is `SQLITE_OK`.
    pub fn isOk(self: Status) bool {
        return self == .ok;
    }
};

/// The storage class of a column value, as `sqlite3_column_type` reports it.
///
/// The five values are `src/sqlite3.h:5356-5359`. This is the class of the
/// value in the row, which is a different question from the column's declared
/// type: `sqlite3_column_type` is declared at `src/sqlite3.h:5589` and
/// `sqlite3_column_decltype` at `:5227`, and neither derives from the other. An
/// expression has no declared type and answers null for `declType`; a value
/// answers one class for `columnType`.
///
/// It is also the class the *accessors* convert from. A caller that reads a
/// column without asking its class first gets a converted value rather than an
/// error: `src/sqlite3.h:5484-5510` is the table of what each accessor does to
/// a value of another class, and "TEXT requested, INTEGER internal" is an ASCII
/// rendering rather than a refusal.
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

    /// The number upstream returned, for any code.
    pub fn code(self: ColumnType) c_int {
        return @intFromEnum(self);
    }

    /// The class this code names, or null when it is not one of the five.
    pub fn fromCode(raw: c_int) ?ColumnType {
        return std.enums.fromInt(ColumnType, raw);
    }
};

/// The flags `sqlite3_open_v2` takes, as a struct of independent bits.
///
/// Every field defaults to false, so `.{ .readwrite = true }` and `.{}` are both
/// valid literals and a partial literal cannot mean something other than what
/// it says. The bit values are `src/sqlite3.h:603-624`; the flags upstream marks
/// "VFS only" are deliberately absent, because `src/sqlite3.h:590-591` says only
/// the ones marked "Ok for sqlite3_open_v2()" may be passed to this function,
/// and `src/sqlite3.h:3815-3818` says the behaviour for any other combination
/// is undefined.
///
/// `src/sqlite3.h:3741-3744` states the required combination: at least one of
/// `readonly`, or `readwrite` together with `create`. `Db.open` checks that
/// before calling, and returns `error.NoOpenMode` rather than passing a
/// combination upstream says is undefined.
pub const OpenFlags = packed struct(u32) {
    /// `SQLITE_OPEN_READONLY`, `src/sqlite3.h:603`. Open read-only.
    readonly: bool = false,
    /// `SQLITE_OPEN_READWRITE`, `:604`. Open for reading and writing.
    readwrite: bool = false,
    /// `SQLITE_OPEN_CREATE`, `:605`. Create the database if it does not exist.
    create: bool = false,
    /// `src/sqlite3.h:606-608`: DELETEONCLOSE, EXCLUSIVE and AUTOPROXY, all
    /// marked "VFS only". The struct holds the header's own bit positions, so
    /// the bits that are not exposed are spelled as reserved fields. They are
    /// never set, and `bits()` never publishes them.
    reserved_1: u3 = 0,
    /// `SQLITE_OPEN_URI`, `:609`. The filename may be a `file:` URI.
    uri: bool = false,
    /// `SQLITE_OPEN_MEMORY`, `:610`. An in-memory database. Needs no path.
    memory: bool = false,
    /// `src/sqlite3.h:611-617`: MAIN_DB, TEMP_DB, TRANSIENT_DB, the four
    /// journals and SUPER_JOURNAL, all "VFS only".
    reserved_2: u7 = 0,
    /// `SQLITE_OPEN_NOMUTEX`, `:618`. "multi-thread" threading mode: one
    /// connection per thread.
    nomutex: bool = false,
    /// `SQLITE_OPEN_FULLMUTEX`, `:619`. "serialized" threading mode: many
    /// threads may share one connection. This is also what the compiled library
    /// defaults to on every target but WASI (`src/sqlite3.c:15106-15111`), so a
    /// caller that asks for nothing gets it.
    fullmutex: bool = false,
    /// `SQLITE_OPEN_SHAREDCACHE`, `:620`. Shared cache, overriding the global
    /// setting. Upstream discourages shared cache (`src/sqlite3.h:3794-3796`)
    /// and this build leaves it off by default.
    sharedcache: bool = false,
    /// `SQLITE_OPEN_PRIVATECACHE`, `:621`. Private cache, overriding the global
    /// setting.
    privatecache: bool = false,
    /// `src/sqlite3.h:622`: WAL, "VFS only".
    reserved_3: u5 = 0,
    /// `SQLITE_OPEN_NOFOLLOW`, `:623`. The filename may not contain a symlink.
    nofollow: bool = false,
    /// `SQLITE_OPEN_EXRESCODE`, `:624`. Come up in extended result code mode,
    /// and return an extended code from the open itself.
    exrescode: bool = false,
    /// `src/sqlite3.h:626`: the reserved range and the rest of the word.
    reserved_4: u6 = 0,
    /// The `int` `sqlite3_open_v2` takes, or null when the combination is not
    /// one `src/sqlite3.h:3741-3744` permits.
    ///
    /// The two conflicting threading bits are rejected here rather than passed:
    /// `src/sqlite3.h:3777-3788` gives `SQLITE_OPEN_NOMUTEX` and
    /// `SQLITE_OPEN_FULLMUTEX` each a meaning, and passing both leaves which one
    /// applies to the reader's guess.
    pub fn bits(self: OpenFlags) ?c_int {
        if (self.nomutex and self.fullmutex) return null;
        if (self.sharedcache and self.privatecache) return null;
        // `src/sqlite3.h:3741-3744`: one of READONLY, or READWRITE and
        // CREATE together.
        if (!self.readonly and !(self.readwrite and self.create)) return null;
        return @as(c_int, @intCast(@as(u32, @bitCast(self))));
    }
};

/// Every way this module's own code refuses, cut where it checked.
///
/// Each member is a condition some code in this file tested; none is a guess at
/// what the C API might do. The exact code upstream returned is always
/// available separately - `Db.errcode`, `Db.extendedErrcode`, `sqlite3_errstr`
/// through `c` - because a Zig error carries no payload and discarding the
/// library's own diagnosis would be worse than naming less of it.
pub const Error = error{
    /// `sqlite3_prepare_v2` returned a code other than `SQLITE_OK`. The
    /// statement pointer is NULL and nothing is owned
    /// (`src/sqlite3.h:4540`); `Db.errcode` says which code it was.
    PrepareFailed,
    /// `sqlite3_prepare_v2` returned `SQLITE_OK` and left the statement pointer
    /// NULL, which `src/sqlite3.h:4541-4542` says is what an empty string or a
    /// comment compiles to. Upstream calls this a success; naming it as an error
    /// is this module's decision, and the honest one: the caller asked for a
    /// statement and there is none.
    NoStatement,
    /// `sqlite3_bind_*` returned a code other than `SQLITE_OK`
    /// (`src/sqlite3.h:4996-4998`). The binding did not take; `Db.errcode` on the
    /// connection carries which code it was, and `src/sqlite3.h:4990-4993` says
    /// a bind on a statement that has been stepped more recently than its last
    /// reset is `SQLITE_MISUSE`.
    BindFailed,
    /// `sqlite3_step` returned a code that is neither `SQLITE_ROW` nor
    /// `SQLITE_DONE` (`src/sqlite3.h:479-480`). The statement is still owned and
    /// still finalizable; `Statement.reset` returns it to a runnable state.
    StepFailed,
    /// A column has no value to read: `sqlite3_column_type` answered `.null`
    /// (`src/sqlite3.h:5589`), or the accessor returned NULL where the class was
    /// not NULL and the connection's last code was not `SQLITE_OK` either
    /// (`src/sqlite3.h:5573-5578`). An absent value and a failed conversion
    /// answer the same pointer, and that pair of checks is what tells them
    /// apart - which is why this error exists rather than a silent empty slice.
    NullValue,
    /// `sqlite3_finalize` returned a code other than `SQLITE_OK`. The statement
    /// was destroyed either way (`src/sqlite3.h:5595-5600`); the code is the
    /// most recent evaluation's.
    FinalizeFailed,
    /// `sqlite3_close_v2` returned a code other than `SQLITE_OK`.
    CloseFailed,
    /// The flag combination is not one `src/sqlite3.h:3741-3744` permits. No
    /// platform call was made and no connection exists.
    NoOpenMode,
    /// A column index past `sqlite3_column_count`. Checked before the call,
    /// because upstream's own behaviour for an out-of-range column is to return
    /// a default value or NULL rather than to report an error
    /// (`src/sqlite3.h:5445`), and a silent default is not a contract a caller
    /// can build on.
    ColumnOutOfRange,
};

/// What `sqlite3_step` said.
///
/// `SQLITE_ROW` and `SQLITE_DONE` are the two non-error answers the header gives
/// (`src/sqlite3.h:479-480`), so they are the two members here rather than an
/// `is_done` boolean: a statement that has more rows and one that is finished
/// are not the same state, and a caller can only tell them apart if the type
/// says so.
pub const Step = union(enum) {
    /// `SQLITE_ROW`: another row is ready and the column accessors are valid.
    row,
    /// `SQLITE_DONE`: the statement has finished executing. The column accessors
    /// are not valid.
    done,
};

/// A database connection.
///
/// One optional pointer, owning the `sqlite3` object `sqlite3_open_v2` created.
/// `close` takes `*Db` and clears it, so a closed connection cannot be reached
/// through the same value again. `Db` is a value type: copying it copies the
/// pointer and two copies would both believe they own the connection. Passing it
/// by pointer through a call that outlives it, or copying one out of a
/// container, gives two owners of one `sqlite3` object and is a bug - which is
/// why every method here takes `Db` by value and nothing here hands out a
/// second owning copy.
pub const Db = struct {
    /// The handle, or null once `close` has run.
    handle: ?*c.sqlite3,

    /// Open a connection.
    ///
    /// `filename` is UTF-8 (`src/sqlite3.h:3718`) and NUL-terminated, because
    /// the C parameter is `const char *` and the length is not passed. The
    /// special names upstream defines work as they do there: `":memory:"` is a
    /// private temporary in-memory database that vanishes when the connection
    /// closes (`src/sqlite3.h:3833-3835`), and `""` is a private temporary
    /// on-disk one (`src/sqlite3.h:3841-3843`).
    ///
    /// Three outcomes, not one, because upstream has three. See `OpenResult`.
    pub fn open(filename: [:0]const u8, flags: OpenFlags) OpenError!OpenResult {
        const bits = flags.bits() orelse return error.NoOpenMode;

        var handle: ?*c.sqlite3 = null;
        const code = c.sqlite3_open_v2(filename, &handle, bits, null);
        if (code == c.SQLITE_OK) {
            if (handle == null) {
                // Upstream returns SQLITE_OK with a connection
                // (`src/sqlite3.h:3724-3725`), so a null here is not a code this
                // build knows how to read a message from. It is still reported
                // rather than handed back as a usable value.
                return .{ .no_connection = code };
            }
            return .{ .ok = .{ .handle = handle } };
        }
        if (handle) |live| {
            // The connection is live enough to read the message from, and
            // `src/sqlite3.h:3725-3726` says exactly why upstream returns it
            // that way. It is returned rather than closed here: closing it would
            // free the very string the caller needs.
            return .{ .failed = .{ .db = .{ .handle = live }, .code = code } };
        }
        // `src/sqlite3.h:3721-3723`: the only case upstream names is that SQLite
        // could not allocate the object. Nothing was opened and nothing is
        // published.
        return .{ .no_connection = code };
    }

    /// Close the connection and clear this value.
    ///
    /// `sqlite3_close_v2` rather than `sqlite3_close`, for the reason upstream
    /// gives at `src/sqlite3.h:335-343`: it returns `SQLITE_OK` even when
    /// statements are still open, marking the connection unusable and
    /// deallocating it once they are finalized. That is the destructor a
    /// garbage-collected host needs and the honest one for a Zig `defer` in an
    /// error path. A caller that wants to know that nothing was left open calls
    /// `closeChecked` instead.
    ///
    /// The connection is always released eventually, so this returns nothing. A
    /// non-`SQLITE_OK` answer is still worth having, which is what
    /// `closeChecked` is for.
    pub fn close(self: *Db) void {
        if (self.handle) |live| {
            _ = c.sqlite3_close_v2(live);
            self.handle = null;
        }
    }

    /// Close and report the code.
    ///
    /// The same call as `close`, with the result checked. On an error the handle
    /// is still cleared: the connection has been handed to SQLite either way and
    /// this module cannot un-hand it.
    pub fn closeChecked(self: *Db) Error!void {
        if (self.handle) |live| {
            const code = c.sqlite3_close_v2(live);
            self.handle = null;
            if (code != c.SQLITE_OK) return error.CloseFailed;
            return;
        }
    }

    /// Compile one statement.
    ///
    /// `sql` is UTF-8 and NUL-terminated; `src/sqlite3.h:4527-4530` notes that
    /// passing the byte count *including* the terminator is a small performance
    /// advantage over -1, which is what this does.
    ///
    /// On `SQLITE_OK` with a statement, the statement is owned by the returned
    /// value and must be `finalize`d. On any error nothing is owned. On
    /// `SQLITE_OK` with no statement the input was empty or only a comment
    /// (`src/sqlite3.h:4541-4542`) and that is `error.NoStatement`.
    ///
    /// This compiles the *first* statement in the text, exactly as upstream
    /// does (`src/sqlite3.h:4534-4537`); the rest is left uncompiled and not
    /// reported, because a `prepare` that took a tail would have to return two
    /// things at once.
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

    /// Run a statement that produces no rows, and finalize it.
    ///
    /// A convenience for the one case where the whole of open/prepare/step/
    /// finalize is a single thing a caller wants: `CREATE TABLE`, `INSERT`,
    /// `BEGIN`. The step loop runs to `SQLITE_DONE` and the statement is
    /// finalized before this returns, on the error path too - so a failed
    /// `exec` leaves no statement behind. `finalize` is called with `catch {}`
    /// on the error path because the interesting code is the one that failed
    /// earlier and `Db.errcode` already carries it.
    pub fn exec(self: Db, sql: [:0]const u8) Error!void {
        var statement = try self.prepare(sql);
        defer statement.finalize() catch {};
        _ = statement.runToCompletion() catch |err| return err;
    }

    /// The most recent result code for this connection, unchanged.
    ///
    /// `sqlite3_errcode`, `src/sqlite3.h:4244`. Read it to turn a `NullValue`
    /// into an SQL NULL or an allocation failure, which `src/sqlite3.h:5575-5578`
    /// says is the only way to tell those two apart.
    pub fn errcode(self: Db) c_int {
        return c.sqlite3_errcode(self.handle);
    }

    /// The most recent extended result code, unchanged.
    ///
    /// `sqlite3_extended_errcode`, `src/sqlite3.h:4245`. An extended code is the
    /// primary code with bits in the high byte (`src/sqlite3.h:500`); this
    /// returns it as-is so no information is lost, and `Status.fromExtendedCode`
    /// is the function that takes the primary part.
    pub fn extendedErrcode(self: Db) c_int {
        return c.sqlite3_extended_errcode(self.handle);
    }

    /// The primary code, if it is one `Status` knows.
    ///
    /// `Status.fromExtendedCode` applied to `sqlite3_errcode`, which answers the
    /// primary code for an ordinary failure and the primary part for an extended
    /// one.
    pub fn errStatus(self: Db) ?Status {
        return Status.fromExtendedCode(self.errcode());
    }

    /// The library's own English description of the most recent failure.
    ///
    /// `sqlite3_errmsg`, `src/sqlite3.h:4246`. Borrowed from the connection: the
    /// pointer is the provider's, and it is valid until the next call on this
    /// connection. `src/sqlite3.h:4240-4243` warns that after `SQLITE_MISUSE` the
    /// code and message may or may not be set, which is why this returns the
    /// header's `const char *` as a NUL-terminated slice rather than promising
    /// more than that.
    pub fn errmsg(self: Db) [:0]const u8 {
        return std.mem.span(c.sqlite3_errmsg(self.handle));
    }

    /// The rowid of the most recent successful insert on this connection.
    ///
    /// `sqlite3_last_insert_rowid`, `src/sqlite3.h:2795`.
    pub fn lastInsertRowid(self: Db) i64 {
        return c.sqlite3_last_insert_rowid(self.handle);
    }

    /// Rows changed by the most recent statement.
    ///
    /// `sqlite3_changes`, `src/sqlite3.h:2870`, which the header types as `int`;
    /// this returns it as `i64` because that is what a row count means and the
    /// widening is exact.
    pub fn changes(self: Db) i64 {
        return @intCast(c.sqlite3_changes(self.handle));
    }

    /// Whether the connection has a transaction open.
    ///
    /// `sqlite3_txn_state`, `src/sqlite3.h:7060`, with the schema name `"main"`
    /// because that is the database `sqlite3_open_v2` opens. The three answers
    /// are 0 for none, 1 for a write transaction and 2 for a read transaction
    /// (`src/sqlite3.h:7047-7058`).
    pub fn inTransaction(self: Db) bool {
        return c.sqlite3_txn_state(self.handle, "main") != 0;
    }
};

/// What `Db.open` produced.
///
/// Three shapes, because upstream has three (`src/sqlite3.h:3719-3726`): a
/// success, a failure that still handed back a connection so the message can be
/// read, and a failure with no connection at all. One Zig error cannot carry
/// both a borrowed message and a missing handle, so the connection is part of
/// the return value and the code is a field.
pub const OpenResult = union(enum) {
    /// `SQLITE_OK` and a live connection.
    ok: Db,
    /// A code other than `SQLITE_OK`, with the connection upstream still
    /// returned. It is open enough to read `errmsg` from and **must be closed**.
    failed: struct {
        /// The connection to read the message from, and to close.
        db: Db,
        /// The code `sqlite3_open_v2` returned, unchanged.
        code: c_int,
        /// The message, read through the connection above.
        pub fn message(self: @This()) [:0]const u8 {
            return self.db.errmsg();
        }
    },
    /// A code other than `SQLITE_OK` and no connection at all, which
    /// `src/sqlite3.h:3721-3723` names as SQLite being unable to allocate the
    /// object. Nothing was opened and there is nothing to close.
    no_connection: c_int,
};

/// `Db.open`'s only failure: the flags are not a combination upstream permits.
const OpenError = error{NoOpenMode};

/// A prepared statement.
///
/// One pointer, owning the `sqlite3_stmt` `sqlite3_prepare_v2` created.
/// `finalize` takes the statement *by value*, so the handle is consumed by the
/// call and cannot be finalized twice through the same value; that is why
/// `exec` above can `defer statement.finalize() catch {}` and why a caller
/// cannot hold a copy and finalize both. A `Statement` copied by value has two
/// owners of one `sqlite3_stmt`; passing one into a call that outlives it does
/// the same, and `sqlite3_finalize` on the second would reach freed memory.
pub const Statement = struct {
    /// The handle.
    handle: *c.sqlite3_stmt,

    /// How many columns the statement produces.
    ///
    /// `sqlite3_column_count`, `src/sqlite3.h:5116`. This is a property of the
    /// compiled statement and is readable before the first `step`.
    pub fn columnCount(self: Statement) usize {
        const count = c.sqlite3_column_count(self.handle);
        return if (count < 0) 0 else @intCast(count);
    }

    /// The name of column `index`, or null past the end.
    ///
    /// `sqlite3_column_name`, `src/sqlite3.h:5145`. Borrowed from the statement
    /// and valid until it is finalized, per the same lifetime as
    /// `src/sqlite3.h:5553-5555`. A statement that produces no rows - a `CREATE`,
    /// an `INSERT` - has no columns, and this answers null rather than a name.
    pub fn columnName(self: Statement, index: usize) ?[:0]const u8 {
        if (index >= self.columnCount()) return null;
        return std.mem.span(c.sqlite3_column_name(self.handle, @intCast(index)));
    }

    /// The declared type of column `index`, or null.
    ///
    /// `sqlite3_column_decltype`, `src/sqlite3.h:5227`, which returns NULL for a
    /// column with no declared type - an expression, or any column of a result
    /// computed rather than read from a table. That is a different question from
    /// `ColumnType`, which is the class of the value actually in the row.
    pub fn declType(self: Statement, index: usize) ?[:0]const u8 {
        if (index >= self.columnCount()) return null;
        const declared = c.sqlite3_column_decltype(self.handle, @intCast(index));
        if (isNull(@TypeOf(declared), declared)) return null;
        return std.mem.span(declared);
    }

    /// The storage class of column `index` in the current row.
    ///
    /// `sqlite3_column_type`, `src/sqlite3.h:5589`. Only meaningful after a
    /// `step` that returned `.row`; before the first step and after `.done`
    /// upstream answers for an absent row rather than reporting an error, so
    /// this is documented as requiring a row rather than checked here.
    pub fn columnType(self: Statement, index: usize) ?ColumnType {
        if (index >= self.columnCount()) return null;
        return ColumnType.fromCode(c.sqlite3_column_type(self.handle, @intCast(index)));
    }

    /// Advance the statement.
    ///
    /// `sqlite3_step`, `src/sqlite3.h:5312`. `.row` means the column accessors
    /// are valid until the next `step`, `reset` or `finalize`
    /// (`src/sqlite3.h:5553-5555`); `.done` means the statement finished.
    ///
    /// A code that is neither is `error.StepFailed`, and the statement is still
    /// owned and still finalizable - upstream requires the `sqlite3_reset` that
    /// `reset` wraps before a failed statement is run again
    /// (`src/sqlite3.h:4570-4572`).
    pub fn step(self: Statement) Error!Step {
        return switch (c.sqlite3_step(self.handle)) {
            c.SQLITE_ROW => .row,
            c.SQLITE_DONE => .done,
            else => error.StepFailed,
        };
    }

    /// Step until the statement is finished.
    ///
    /// For a statement that produces no rows, which is every `exec` uses. The
    /// `SQLITE_ROW` case is unreachable for such a statement; if one arrives it
    /// is an `error.StepFailed` rather than a silently discarded row.
    pub fn runToCompletion(self: Statement) Error!void {
        while (true) {
            switch (try self.step()) {
                .done => return,
                .row => return error.StepFailed,
            }
        }
    }

    /// The integer in column `index`.
    ///
    /// `sqlite3_column_int64`, `src/sqlite3.h:5583`. The accessor converts
    /// rather than refusing: `src/sqlite3.h:5484-5510` is the table of what each
    /// accessor does to a value of another class, and "INTEGER requested" from
    /// an internal FLOAT is a cast. An absent column is `error.ColumnOutOfRange`
    /// rather than 0, because the header types the narrower sibling as `int`
    /// (`src/sqlite3.h:5582`) with no out-of-range answer at all, and a silent
    /// zero is not a value a caller can tell from a real one.
    pub fn columnInt64(self: Statement, index: usize) Error!i64 {
        try self.checkColumn(index);
        return c.sqlite3_column_int64(self.handle, @intCast(index));
    }

    /// The floating-point value in column `index`.
    ///
    /// `sqlite3_column_double`, `src/sqlite3.h:5581`, with the same conversion
    /// caveat and the same out-of-range refusal as `columnInt64`.
    pub fn columnDouble(self: Statement, index: usize) Error!f64 {
        try self.checkColumn(index);
        return c.sqlite3_column_double(self.handle, @intCast(index));
    }

    /// The UTF-8 text in column `index`.
    ///
    /// `sqlite3_column_text` followed by `sqlite3_column_bytes`, which is the
    /// order `src/sqlite3.h:5536-5543` prescribes and the one that makes the
    /// length right: the text call forces any conversion, and the bytes call
    /// then measures the result.
    ///
    /// **The slice is borrowed**, not owned and not to be freed
    /// (`src/sqlite3.h:5553-5558`): it points into memory the library owns, it
    /// is valid until a type conversion occurs, until the next `step`, `reset`
    /// or `finalize`, and it must never be passed to `sqlite3_free`. Copy it if
    /// it has to outlive the row.
    ///
    /// `error.NullValue` is what a NULL return means. `src/sqlite3.h:5460-5463`
    /// says a TEXT request against an internally NULL value answers a NULL
    /// pointer, and `:5573-5574` says the same answer covers a failed conversion;
    /// `:5575-5578` says `Db.errcode` immediately afterwards is what tells the
    /// two apart. An empty string is *not* this error:
    /// `src/sqlite3.h:5461-5463` says strings from `sqlite3_column_text` are
    /// zero-terminated "even empty strings", so a zero-length value comes back as
    /// a valid empty slice.
    pub fn columnText(self: Statement, index: usize) Error![]const u8 {
        try self.checkColumn(index);
        const text = c.sqlite3_column_text(self.handle, @intCast(index));
        if (isNull(@TypeOf(text), text)) return error.NullValue;
        const len = c.sqlite3_column_bytes(self.handle, @intCast(index));
        return text[0..@intCast(len)];
    }

    /// The bytes in column `index`, whether it is a BLOB or text.
    ///
    /// `sqlite3_column_blob` followed by `sqlite3_column_bytes`, the second
    /// ordering `src/sqlite3.h:5536-5543` prescribes. Same borrowed lifetime
    /// and the same "never `sqlite3_free` it" as `columnText`.
    ///
    /// A text column read through this returns its UTF-8 bytes; use `columnText`
    /// when the difference between "a BLOB" and "text that happens to be
    /// well-formed" matters, which is what `columnType` is for.
    ///
    /// `error.NullValue` here means an **absent** value, and the class check is
    /// what makes that exact. `src/sqlite3.h:5464-5465` says the return value
    /// from `sqlite3_column_blob` *for a zero-length BLOB is a NULL pointer*, so
    /// a NULL pointer here is either an empty value, an SQL NULL or a failed
    /// conversion, and the pointer alone cannot tell them apart. The class can:
    /// `sqlite3_column_type` answers `.null` for an absent value. What is left
    /// after that is an empty value or an allocation failure, and
    /// `src/sqlite3.h:5575-5578` names the way to tell those: read
    /// `sqlite3_errcode` on the connection. `sqlite3_db_handle`
    /// (`src/sqlite3.h:6978`) gets that connection from this statement, so the
    /// check is made here rather than left to the caller - and an empty BLOB comes
    /// back as an empty slice, which is what it is.
    pub fn columnBlob(self: Statement, index: usize) Error![]const u8 {
        try self.checkColumn(index);
        // `checkColumn` above has already refused an index past the end, and
        // `columnType` refuses exactly the same indices, so the class is known
        // here rather than optional.
        if (self.columnType(index).? == .null) return error.NullValue;
        const bytes = c.sqlite3_column_blob(self.handle, @intCast(index));
        if (isNull(@TypeOf(bytes), bytes)) {
            // Not SQL NULL, so `src/sqlite3.h:5573-5578` leaves a failed
            // conversion, and the prescribed way to rule it out is the
            // connection's last result code.
            if (c.sqlite3_db_handle(self.handle)) |owner| {
                if (c.sqlite3_errcode(owner) != c.SQLITE_OK) return error.NullValue;
            }
            // The code is OK and the class was not NULL: this is the zero-length
            // BLOB of `src/sqlite3.h:5464-5465`, which is a value.
            return "";
        }
        const len = c.sqlite3_column_bytes(self.handle, @intCast(index));
        const raw: [*]const u8 = @ptrCast(bytes);
        return raw[0..@intCast(len)];
    }

    /// Bind a parameter to an integer.
    ///
    /// `sqlite3_bind_int64`, `src/sqlite3.h:5014`. Parameter indexes are
    /// one-based: `src/sqlite3.h:5060` states it for the whole bind family
    /// ("The first host parameter has an index of 1, not 0").
    ///
    /// The code `src/sqlite3.h:4996-4998` defines is `SQLITE_OK` or an error,
    /// and `:4990-4993` says which error a misuse gets: a NULL statement or one
    /// that has been stepped more recently than its last reset is `SQLITE_MISUSE`.
    /// `Db.errcode` still carries whichever it was.
    pub fn bindInt64(self: Statement, index: usize, value: i64) Error!void {
        const code = c.sqlite3_bind_int64(self.handle, @intCast(index), value);
        if (code != c.SQLITE_OK) return error.BindFailed;
    }

    /// Bind a parameter to a floating-point value.
    ///
    /// `sqlite3_bind_double`, `src/sqlite3.h:5012`.
    pub fn bindDouble(self: Statement, index: usize, value: f64) Error!void {
        const code = c.sqlite3_bind_double(self.handle, @intCast(index), value);
        if (code != c.SQLITE_OK) return error.BindFailed;
    }

    /// Bind a parameter to SQL NULL.
    ///
    /// `sqlite3_bind_null`, `src/sqlite3.h:5015`.
    pub fn bindNull(self: Statement, index: usize) Error!void {
        const code = c.sqlite3_bind_null(self.handle, @intCast(index));
        if (code != c.SQLITE_OK) return error.BindFailed;
    }

    /// Bind a parameter to UTF-8 text.
    ///
    /// `sqlite3_bind_text`, `src/sqlite3.h:5016`, with the length passed
    /// explicitly so that a value containing a NUL is bound whole rather than
    /// truncated at it.
    ///
    /// **SQLite copies the bytes.** The destructor handed over is the address
    /// `SQLITE_TRANSIENT` names (`src/sqlite3.h:6430`), which is the header's own
    /// sentinel for "the library will copy this, so the caller may free it as
    /// soon as this returns" (`src/sqlite3.h:6418-6426`). `SQLITE_STATIC` -
    /// `:6429` - would promise the bytes outlive the statement, and this module
    /// does not make that promise about a slice it was handed. See `transient`
    /// for why the sentinel is carried the way it is.
    pub fn bindText(self: Statement, index: usize, value: []const u8) Error!void {
        const code = if (runtime_loaded)
            c.sqlite3_bind_text(
                self.handle,
                @intCast(index),
                @as([*:0]const u8, @ptrCast(value.ptr)),
                @intCast(value.len),
                c.SQLITE_TRANSIENT,
            )
        else
            sqlite3_bind_text(
                self.handle,
                @intCast(index),
                @as([*:0]const u8, @ptrCast(value.ptr)),
                @intCast(value.len),
                transient,
            );
        if (code != c.SQLITE_OK) return error.BindFailed;
    }

    /// Bind a parameter to raw bytes.
    ///
    /// `sqlite3_bind_blob`, `src/sqlite3.h:5009`, with the same
    /// `SQLITE_TRANSIENT` copy semantics as `bindText`, and for the same reason.
    pub fn bindBlob(self: Statement, index: usize, value: []const u8) Error!void {
        const code = if (runtime_loaded)
            c.sqlite3_bind_blob(
                self.handle,
                @intCast(index),
                @as(*const anyopaque, @ptrCast(value.ptr)),
                @intCast(value.len),
                c.SQLITE_TRANSIENT,
            )
        else
            sqlite3_bind_blob(
                self.handle,
                @intCast(index),
                @as(*const anyopaque, @ptrCast(value.ptr)),
                @intCast(value.len),
                transient,
            );
        if (code != c.SQLITE_OK) return error.BindFailed;
    }

    /// Clear every binding, and return the statement to its prepared state.
    ///
    /// `sqlite3_clear_bindings`, `src/sqlite3.h:5100`, followed by
    /// `sqlite3_reset`, `src/sqlite3.h:5656`. Both are here because both are
    /// needed, and the first is not redundant: `src/sqlite3.h:4993` says
    /// "Bindings are not cleared by the `sqlite3_reset()` routine" and `:4994`
    /// says an unbound parameter is read as NULL - so a statement reused for many
    /// rows would otherwise carry the previous row's values into the next one.
    /// `src/sqlite3.h:4570-4572` is why the reset is here at all: after a failed
    /// step it is the call that makes the statement runnable again.
    ///
    /// Both return codes are discarded, and that is a decision rather than an
    /// oversight. `src/sqlite3.h:5644-5651` names the one case where a reset's
    /// answer is not implied by the step before it - a `RETURNING` clause that
    /// cannot commit can make `sqlite3_reset` return `SQLITE_BUSY` after a
    /// `SQLITE_ROW` - and reporting it here would make every reuse a fallible
    /// call for a case this package never writes. A caller that uses `RETURNING`
    /// reads `Db.errcode` after the loop, where that code is already visible.
    /// `sqlite3_clear_bindings` can only fail on the misuse `:4990-4993`
    /// describes, which a statement from `Db.prepare` cannot be in.
    pub fn reset(self: Statement) void {
        _ = c.sqlite3_clear_bindings(self.handle);
        _ = c.sqlite3_reset(self.handle);
    }

    /// Destroy the statement.
    ///
    /// `sqlite3_finalize`, `src/sqlite3.h:5617`, which the header says can be
    /// called at any point in the statement's life (`src/sqlite3.h:5602`) and
    /// returns the most recent evaluation's code (`src/sqlite3.h:5595-5600`).
    /// That code is checked here rather than discarded: a statement whose last
    /// step failed has something to report, and this is the call that reports it.
    ///
    /// Takes `Statement` by value, so the handle is consumed. There is no second
    /// finalize of the same value and no "already closed" state to represent.
    pub fn finalize(self: Statement) Error!void {
        if (c.sqlite3_finalize(self.handle) != c.SQLITE_OK) return error.FinalizeFailed;
    }

    /// The SQL text this statement was compiled from.
    ///
    /// `sqlite3_sql`, `src/sqlite3.h:4681`. A `prepare_v2` statement carries a
    /// copy of the original text (`src/sqlite3.h:4554-4556`), so this is that
    /// copy rather than the caller's buffer, and `src/sqlite3.h:4671-4673` says
    /// SQLite manages it and frees it when the statement is finalized - which is
    /// why this borrows it and why the value must not outlive `finalize`.
    ///
    /// Not optional, because the header's condition always holds for a statement
    /// from `Db.prepare`: `src/sqlite3.h:4644-4647` scopes it to statements
    /// created by `sqlite3_prepare_v2`, `sqlite3_prepare_v3`,
    /// `sqlite3_prepare16_v2` or `sqlite3_prepare16_v3`, and this module creates
    /// none other. It names no case in which the answer is null - the only
    /// null-returning entry point in that block is `sqlite3_expanded_sql`
    /// (`src/sqlite3.h:4663-4665`), which is a different function with a
    /// different ownership rule.
    pub fn sql(self: Statement) [:0]const u8 {
        return std.mem.span(c.sqlite3_sql(self.handle));
    }

    /// Reject a column index before it reaches the C call.
    fn checkColumn(self: Statement, index: usize) Error!void {
        if (index >= self.columnCount()) return error.ColumnOutOfRange;
    }
};

/// `SQLITE_TRANSIENT` for a linked build: the address itself, and the two bind
/// prototypes that carry it in a linked build only.
///
/// `src/sqlite3.h:6429` defines `SQLITE_TRANSIENT` as
/// `(sqlite3_destructor_type)-1`, and `src/sqlite3.h:6430` says the library
/// compares the destructor it was handed against that address, so what travels
/// is an address and never a callable. translate-c turns the macro into
/// `__helpers.cast(sqlite3_destructor_type, -1)`, and Zig will not hold `-1` in a
/// function pointer on a target whose function pointers are required to be
/// aligned - `?*const fn` is four-byte aligned on `aarch64` and `riscv64` - so
/// the constant does not compile there and neither does any call naming it
/// ("pointer type '?*const fn (?*anyopaque) callconv(.c) void' requires aligned
/// address").
///
/// So in a linked build `bindText` and `bindBlob` call the two prototypes below
/// rather than the translation's, and the only difference from
/// `src/sqlite3.h:5016` and `src/sqlite3.h:5009` is that the destructor is
/// carried as an untyped pointer - which is what a function pointer is in the
/// ABI. `transient` is `maxInt(usize)`, the all-ones address `-1` widens to on
/// every target, so the bits that reach the library are the bits the header's own
/// macro would have produced. All six `zig build check` targets are linked, and
/// all six bind this way.
///
/// A runtime-loaded build has no `sqlite3_bind_text` symbol to call at all:
/// every entry point goes through the generated table, whose destructor field
/// carries the header's own function-pointer type
/// (`runtime/generate.zig` writes the field from the translation). There the
/// translated constant is the only value of that type there is, so the routed
/// branch passes it and this configuration needs
/// `@alignOf(c.sqlite3_destructor_type) == 1` - which every host this route is
/// built for has, and which is a compile-time answer, not a silent difference in
/// what the library is told.
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

/// The version of the library actually linked or loaded.
///
/// `sqlite3_libversion`, `src/sqlite3.h:189`, borrowed from the provider and
/// valid until that provider is unloaded. This is the library's answer about
/// itself, not this package's constant: a runtime-loaded provider is whatever
/// the caller named, and printing what it says is how a caller finds out.
pub fn libraryVersion() [:0]const u8 {
    return std.mem.span(c.sqlite3_libversion());
}

/// The library's version as one number, unchanged.
///
/// `sqlite3_libversion_number`, `src/sqlite3.h:191`. `src/sqlite3.h:130-136`
/// gives the formula: `X * 1000000 + Y * 1000 + Z`, so the major component is
/// this divided by a million and the ABI family of a provider is decided by that
/// component alone.
pub fn libraryVersionNumber() i64 {
    return c.sqlite3_libversion_number();
}

/// The Fossil check-in the loaded library was built from, unchanged.
///
/// `sqlite3_sourceid`, `src/sqlite3.h:190`: a date, a time and a SHA-3 or SHA-1
/// hash of the source tree (`src/sqlite3.h:136-148`). Borrowed from the
/// provider. It is the closest thing upstream publishes to a provenance string
/// for a specific build, and a consumer that wants to record which SQLite it
/// got has this rather than a fork-authored version string.
pub fn sourceId() [:0]const u8 {
    return std.mem.span(c.sqlite3_sourceid());
}

/// Whether this build is thread-safe, as SQLite reports it.
///
/// `sqlite3_threadsafe`, `src/sqlite3.h:259`: 1 for serialized, 2 for
/// multi-thread and 0 for single-thread. This package defines no
/// `SQLITE_THREADSAFE`, so the answer is 1 on every target but WASI, where
/// upstream's own `__wasi__` arm sets it to 0 (`src/sqlite3.c:11676-11685`).
pub fn threadSafe() c_int {
    return c.sqlite3_threadsafe();
}

/// The English text for a result code, or null when the library has none.
///
/// `sqlite3_errstr`, `src/sqlite3.h:4248`. The header's own sentence is the
/// reason this is optional: `src/sqlite3.h:4219-4220` says it "returns the
/// English-language text that describes the result code E, as UTF-8, or NULL if
/// E is not a result code for which a text error message is available". Any
/// integer is a legal argument - the extended codes are codes too, and so is a
/// number that means nothing - so an unconditional string here would be a claim
/// the header does not make.
///
/// Borrowed from a table the provider owns and never to be freed
/// (`src/sqlite3.h:4221-4222`), which is why this hands back the header's
/// `const char *` as a borrowed slice and copies nothing.
pub fn errstr(code: c_int) ?[:0]const u8 {
    const text = c.sqlite3_errstr(code);
    if (isNull(@TypeOf(text), text)) return null;
    return std.mem.span(text);
}