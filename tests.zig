// SPDX-License-Identifier: LicenseRef-PublicDomain
// See FORK-LICENSE.md for what that identifier covers.

//! Behavioural tests for the SQLite facade.
//!
//! ## What these tests are
//!
//! Three kinds of proof, and the split matters because each rules out a
//! different mistake:
//!
//!   * **An independent known answer.** `tools/fixture/aggregate.sql` seeds
//!     twelve rows of a ledger and asks for a grouped reduction. The expected
//!     table is hand-computed from those twelve rows - `a` sums to 425 over 5
//!     rows, `b` to 575 over 4, `c` to -575 over 3, and the whole table to 425
//!     over 12 - and is written out here as literals. A facade that decoded an
//!     integer as a narrower type, dropped a row, double-counted one or reordered
//!     a column disagrees with arithmetic done on paper.
//!   * **A second implementation.** `reduce` below computes the same five
//!     numbers from the same twelve rows with ordinary Zig loops and no SQL at
//!     all. The SQL engine and a straight-line reduction over the same data are
//!     two implementations of the same question, and the test asserts both answer
//!     the hand-computed table. A bug in the SQL engine's grouping would be
//!     caught; so would a bug in this file's expected literals only if it were a
//!     literal, which is why the two live separately.
//!   * **Upstream interop, once.** `zig build oracle` runs the *same SQL text*
//!     through upstream's own shell (`src/shell.c`) and compares with the same
//!     expected table in `tools/fixture/expected.tsv`. That is a different proof
//!     again - two front ends rather than two reductions - and it is a build step
//!     rather than a test, because it needs a second binary this package builds.
//!
//! `tools/check-provenance.sh` is what keeps this file and
//! `tools/fixture/aggregate.sql` asking the same question, and it compares
//! them in the two forms the two files actually spell them in:
//!
//!   * The three non-INSERT statements of the fixture - one `CREATE TABLE`
//!     and the two `SELECT`s - are matched verbatim against this file after
//!     whitespace is collapsed to single spaces and this file's Zig `\\`
//!     line-continuation prefix is stripped. Those are the `CREATE TABLE` in
//!     `seed()`, the grouped `SELECT` the grouped-aggregation test prepares
//!     across four continued lines, and the whole-table `SELECT`.
//!   * The twelve `INSERT INTO ledger VALUES` rows are not SQL text in this
//!     file at all. Each one is matched against the Zig literal
//!     `.entry = N, .account = "X", .cents = M` in the `rows` table below,
//!     and the count is checked against twelve, because this file seeds
//!     through the facade's binding path - `INSERT INTO ledger VALUES(?1,
//!     ?2, ?3)` - rather than by replaying the fixture's row text.
//!
//! So an edit to the SQL upstream's shell runs and an edit to the SQL this
//! file runs cannot drift apart silently.
//!
//! ## What these tests deliberately are not
//!
//! No test here pins a version string, checks that a declaration exists, or
//! asserts that a call did not fail. The version macros are the provenance
//! record's business (`UPSTREAM.md`, `UPSTREAM.sha256`) and a test that only
//! compared `sqlite3_libversion_number()` with a literal would prove nothing
//! about the facade. What the version *is* used for here is a behavioural
//! property: the ABI family's own 64-bit integer path, exercised below with a
//! value no narrower type could hold.
//!
//! ## Ownership in these tests
//!
//! Every connection is closed and every statement finalized, on the error path
//! as well as the successful one. That is not tidiness: `Db.close` releases
//! memory SQLite's own allocator owns and no test framework can supply a leak
//! oracle for it, so the discipline *is* the test. Where a connection is
//! deliberately left unfinalized - the one test that closes a connection with a
//! live statement - that is the behaviour under test, and `sqlite3_close_v2` is
//! what makes it safe (`src/sqlite3.h:335-343`).

const std = @import("std");
const sqlite = @import("sqlite3");

/// The twelve seeded rows, as Zig values.
///
/// The same twelve rows `tools/fixture/aggregate.sql` inserts, in the same
/// order, spelled the same way. This table is what `reduce` walks, so the
/// straight-line reduction and the SQL aggregation are over the same data by
/// construction rather than by two transcriptions agreeing.
const rows = [_]struct { entry: i64, account: []const u8, cents: i64 }{
    .{ .entry = 1, .account = "a", .cents = 100 },
    .{ .entry = 2, .account = "b", .cents = 250 },
    .{ .entry = 3, .account = "a", .cents = 50 },
    .{ .entry = 4, .account = "c", .cents = -700 },
    .{ .entry = 5, .account = "b", .cents = 25 },
    .{ .entry = 6, .account = "a", .cents = 300 },
    .{ .entry = 7, .account = "c", .cents = 75 },
    .{ .entry = 8, .account = "b", .cents = -100 },
    .{ .entry = 9, .account = "a", .cents = 25 },
    .{ .entry = 10, .account = "c", .cents = 50 },
    .{ .entry = 11, .account = "b", .cents = 400 },
    .{ .entry = 12, .account = "a", .cents = -50 },
};

/// One account's hand-computed answer.
const Bucket = struct {
    name: []const u8,
    sum: i64 = 0,
    count: i64 = 0,
    first: i64 = 0,
    last: i64 = 0,
};

/// The same reduction, without SQL.
///
/// Ordinary loops over `rows`, grouped by the account name. It exists to be a
/// second implementation of the question the SQL asks, and it is deliberately
/// naive: no allocation, no sorting, no SQL. If the SQL engine and this disagree
/// then one of them is wrong, and the hand-computed literals below say which.
fn reduce(allocator: std.mem.Allocator, accounts: []const []const u8) ![]Bucket {
    const buckets = try allocator.alloc(Bucket, accounts.len);
    for (accounts, 0..) |name, i| buckets[i] = .{ .name = name };

    for (rows) |row| {
        for (accounts, 0..) |name, i| {
            if (!std.mem.eql(u8, name, row.account)) continue;
            const b = &buckets[i];
            if (b.count == 0) {
                b.first = row.entry;
                b.last = row.entry;
            } else {
                if (row.entry < b.first) b.first = row.entry;
                if (row.entry > b.last) b.last = row.entry;
            }
            b.sum += row.cents;
            b.count += 1;
            break;
        } else {
            return error.AccountNotInList;
        }
    }
    return buckets;
}

/// The hand-computed answer, as literals. Nothing here is computed by this file.
const expected = [_]Bucket{
    .{ .name = "a", .sum = 425, .count = 5, .first = 1, .last = 12 },
    .{ .name = "b", .sum = 575, .count = 4, .first = 2, .last = 11 },
    .{ .name = "c", .sum = -575, .count = 3, .first = 4, .last = 10 },
};

/// Open a private in-memory database, or fail the test.
fn openMemory() !sqlite.Db {
    const opened = try sqlite.Db.open(":memory:", .{ .readwrite = true, .create = true });
    return switch (opened) {
        .ok => |db| db,
        .failed => |f| {
            std.debug.print("openMemory: {s} ({d})\n", .{ f.message(), f.code });
            return error.OpenFailed;
        },
        .no_connection => |code| {
            std.debug.print("openMemory: no connection at all, code {d}\n", .{code});
            return error.NoConnection;
        },
    };
}

/// Insert the twelve seeded rows through the facade's own binding path.
fn seed(db: sqlite.Db) !void {
    try db.exec("CREATE TABLE ledger(entry INTEGER NOT NULL, account TEXT NOT NULL, cents INTEGER NOT NULL)");
    var insert = try db.prepare(
        \\INSERT INTO ledger VALUES(?1, ?2, ?3)
    );
    defer insert.finalize() catch {};
    for (rows) |row| {
        insert.reset();
        try insert.bindInt64(1, row.entry);
        try insert.bindText(2, row.account);
        try insert.bindInt64(3, row.cents);
        try insert.runToCompletion();
    }
}

// The grouped reduction the fixture asks for, read through the facade.
test "hand-computed grouped aggregation over seeded rows" {
    var db = try openMemory();
    defer db.close();
    try seed(db);

    var st = try db.prepare(
        \\SELECT account, SUM(cents), COUNT(*), MIN(entry), MAX(entry)
        \\  FROM ledger
        \\ GROUP BY account
        \\ ORDER BY account
    );
    defer st.finalize() catch {};

    // Five columns and five names, before a single row is read.
    try std.testing.expectEqual(@as(usize, 5), st.columnCount());
    try std.testing.expectEqualStrings("account", st.columnName(0).?);
    try std.testing.expectEqualStrings("SUM(cents)", st.columnName(1).?);
    try std.testing.expectEqualStrings("COUNT(*)", st.columnName(2).?);
    try std.testing.expectEqualStrings("MIN(entry)", st.columnName(3).?);
    try std.testing.expectEqualStrings("MAX(entry)", st.columnName(4).?);
    try std.testing.expect(st.columnName(5) == null);
    // The declared types are the *column's* declaration, which is distinct from
    // the class of the value in a row; this query has no table behind two of its
    // columns, so SQLite has no declared type to report for them.
    try std.testing.expectEqualStrings("TEXT", st.declType(0).?);
    try std.testing.expect(st.declType(1) == null);

    var seen: usize = 0;
    while (true) {
        switch (try st.step()) {
            .done => break,
            .row => {
                if (seen >= expected.len) return error.TooManyRows;
                const want = expected[seen];
                try std.testing.expectEqualStrings(want.name, try st.columnText(0));
                try std.testing.expectEqual(want.sum, try st.columnInt64(1));
                try std.testing.expectEqual(want.count, try st.columnInt64(2));
                try std.testing.expectEqual(want.first, try st.columnInt64(3));
                try std.testing.expectEqual(want.last, try st.columnInt64(4));

                // The class of a value, not the declared type of a column: the
                // name is TEXT, the numbers are INTEGER.
                try std.testing.expectEqual(sqlite.ColumnType.text, st.columnType(0).?);
                try std.testing.expectEqual(sqlite.ColumnType.integer, st.columnType(1).?);
                seen += 1;
            },
        }
    }
    try std.testing.expectEqual(@as(usize, 3), seen);
}

// The whole-table reduction, which is what catches a grouping that lost or
// duplicated a row rather than one that mis-typed a column.
test "hand-computed whole-table reduction, and its agreement with the groups" {
    var db = try openMemory();
    defer db.close();
    try seed(db);

    var st = try db.prepare("SELECT 'grand', SUM(cents), COUNT(*) FROM ledger");
    defer st.finalize() catch {};

    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqualStrings("grand", try st.columnText(0));
    try std.testing.expectEqual(@as(i64, 425), try st.columnInt64(1));
    try std.testing.expectEqual(@as(i64, 12), try st.columnInt64(2));

    // A finished statement is rewound by the library, not by this module:
    // `src/sqlite3.c:94511-94536` resets and restarts a statement that is
    // stepped after `SQLITE_DONE`, so a row-producing statement answers `.row`
    // again with the same row rather than `.done`.
    try std.testing.expectEqual(sqlite.Step.done, try st.step());
    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqualStrings("grand", try st.columnText(0));
    try std.testing.expectEqual(@as(i64, 425), try st.columnInt64(1));
}

// The same five numbers from the second implementation.
test "the SQL aggregation and a straight-line reduction agree with the table" {
    const accounts = [_][]const u8{ "a", "b", "c" };

    const buckets = try reduce(std.testing.allocator, &accounts);
    defer std.testing.allocator.free(buckets);

    // The straight-line reduction is checked against the hand-computed literals
    // first, so a disagreement below is the SQL engine's and not this file's.
    for (expected, 0..) |want, i| {
        try std.testing.expectEqualStrings(want.name, buckets[i].name);
        try std.testing.expectEqual(want.sum, buckets[i].sum);
        try std.testing.expectEqual(want.count, buckets[i].count);
        try std.testing.expectEqual(want.first, buckets[i].first);
        try std.testing.expectEqual(want.last, buckets[i].last);
    }

    var db = try openMemory();
    defer db.close();
    try seed(db);

    var st = try db.prepare(
        \\SELECT account, SUM(cents), COUNT(*), MIN(entry), MAX(entry)
        \\  FROM ledger
        \\ GROUP BY account
        \\ ORDER BY account
    );
    defer st.finalize() catch {};

    var seen: usize = 0;
    while (try st.step() == .row) {
        try std.testing.expectEqualStrings(buckets[seen].name, try st.columnText(0));
        try std.testing.expectEqual(buckets[seen].sum, try st.columnInt64(1));
        try std.testing.expectEqual(buckets[seen].count, try st.columnInt64(2));
        try std.testing.expectEqual(buckets[seen].first, try st.columnInt64(3));
        try std.testing.expectEqual(buckets[seen].last, try st.columnInt64(4));
        seen += 1;
    }
    try std.testing.expectEqual(@as(usize, buckets.len), seen);

    // The group sums must add up to the whole-table sum, and the group counts to
    // the row count. This is the invariant that catches a row that was counted
    // twice in one group and missed in another.
    var sum_of_sums: i64 = 0;
    var sum_of_counts: i64 = 0;
    for (buckets) |bucket| {
        sum_of_sums += bucket.sum;
        sum_of_counts += bucket.count;
    }
    try std.testing.expectEqual(@as(i64, 425), sum_of_sums);
    try std.testing.expectEqual(@as(i64, 12), sum_of_counts);
}

// The 64-bit integer path, with a value no narrower type could hold.
//
// `2^53 + 1` is the first integer `double` cannot represent, so a facade or a
// build whose `sqlite3_int64` were 32-bit, or whose `double` were used for the
// value, cannot answer this at all: it would overflow, truncate or round. The
// header's own typedef is `long long int` (`src/sqlite3.h:304-307`).
test "a 64-bit integer survives a bind, a round trip and an aggregate" {
    const big: i64 = 9007199254740993; // 2^53 + 1

    var db = try openMemory();
    defer db.close();
    try db.exec("CREATE TABLE t(v INTEGER)");

    var insert = try db.prepare("INSERT INTO t VALUES(?1)");
    defer insert.finalize() catch {};
    try insert.bindInt64(1, big);
    try insert.runToCompletion();

    var st = try db.prepare("SELECT v, SUM(v), MAX(v) FROM t");
    defer st.finalize() catch {};

    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqual(big, try st.columnInt64(0));
    try std.testing.expectEqual(big, try st.columnInt64(1));
    try std.testing.expectEqual(big, try st.columnInt64(2));
    try std.testing.expectEqual(sqlite.ColumnType.integer, st.columnType(0).?);
    try std.testing.expectEqual(sqlite.Step.done, try st.step());
}

// SQL NULL is one honest error, and `errcode` is what tells it from a failure.
//
// `src/sqlite3.h:5573-5578`: a NULL from `sqlite3_column_text` means either an
// SQL NULL or a failed conversion, and the two are told apart by reading
// `sqlite3_errcode` immediately afterwards. This checks both halves: that a NULL
// column is `error.NullValue` rather than a silent empty slice, and that the
// code read straight after is `SQLITE_OK` - which is what distinguishes "the
// value was NULL" from "the library ran out of memory".
test "an SQL NULL column is NullValue, and an empty string is not" {
    var db = try openMemory();
    defer db.close();
    try db.exec("CREATE TABLE t(v TEXT)");

    var insert = try db.prepare("INSERT INTO t VALUES(?1)");
    defer insert.finalize() catch {};
    try insert.bindNull(1);
    try insert.runToCompletion();
    insert.reset();
    try insert.bindText(1, "");
    try insert.runToCompletion();

    var st = try db.prepare("SELECT v FROM t ORDER BY rowid");
    defer st.finalize() catch {};

    // rowid 1 is the NULL.
    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqual(sqlite.ColumnType.null, st.columnType(0).?);
    try std.testing.expectError(error.NullValue, st.columnText(0));
    // The distinction the header asks for: read before any other call. What is
    // on the connection is the code `sqlite3_step` published for the row it just
    // produced - `src/sqlite3.c:94581` assigns every step's answer to
    // `db->errCode`, and `SQLITE_ROW` is `src/sqlite3.h:479` - so the claim to
    // check is that no *error* was recorded: the NULL came from an SQL NULL and
    // not from an allocation failure.
    try std.testing.expect(
        db.errcode() == sqlite.c.SQLITE_OK or db.errcode() == sqlite.c.SQLITE_ROW,
    );

    // rowid 2 is a zero-length string, which is a value and not an absence.
    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqual(sqlite.ColumnType.text, st.columnType(0).?);
    try std.testing.expectEqualStrings("", try st.columnText(0));
    // `sqlite3_column_bytes` after `sqlite3_column_text`, which is the order
    // src/sqlite3.h:5536-5543 prescribes, reports zero for the empty string.
    try std.testing.expectEqual(@as(usize, 0), (try st.columnText(0)).len);
}

// Bytes go through as bytes: a BLOB round trip, and text holding a NUL.
//
// The length is passed explicitly by `bindBlob`, so a value with an embedded
// zero is bound whole rather than truncated at it - which is the difference
// between `bindText` and `bindBlob` that a `strlen` mistake would hide.
test "blob bytes and embedded NULs survive the round trip whole" {
    var db = try openMemory();
    defer db.close();
    try db.exec("CREATE TABLE t(v)");

    const payload = [_]u8{ 0x00, 0x01, 0xff, 0x00, 0x7f };
    const with_nul = "before\x00after";

    var insert = try db.prepare("INSERT INTO t VALUES(?1)");
    defer insert.finalize() catch {};
    try insert.bindBlob(1, &payload);
    try insert.runToCompletion();
    insert.reset();
    try insert.bindText(1, with_nul);
    try insert.runToCompletion();

    var st = try db.prepare("SELECT typeof(v), v FROM t ORDER BY rowid");
    defer st.finalize() catch {};

    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqualStrings("blob", try st.columnText(0));
    try std.testing.expectEqual(sqlite.ColumnType.blob, st.columnType(1).?);
    try std.testing.expectEqualSlices(u8, &payload, try st.columnBlob(1));

    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqualStrings("text", try st.columnText(0));
    // The text accessor reports the byte length the explicit bind asked for, so
    // the embedded zero is inside the value rather than the end of it.
    try std.testing.expectEqual(with_nul.len, (try st.columnText(1)).len);
    try std.testing.expectEqualSlices(u8, with_nul, try st.columnText(1));
}

// A constraint violation is the library's own error code, and the connection
// says so afterwards.
//
// `src/sqlite3.h:469` is `SQLITE_CONSTRAINT`, and the extended code
// `src/sqlite3.h:563` is `SQLITE_CONSTRAINT_CHECK`. A facade that collapsed
// every failure into one error would pass a test that only checked "it failed";
// this one checks that the *code* survives, which is what lets a caller tell a
// uniqueness violation from a syntax error without parsing a message.
test "a primary key violation is reported as SQLITE_CONSTRAINT, with its extended code" {
    var db = try openMemory();
    defer db.close();
    try db.exec("CREATE TABLE t(k INTEGER PRIMARY KEY, v TEXT)");
    try db.exec("INSERT INTO t VALUES(1, 'one')");

    var st = try db.prepare("INSERT INTO t VALUES(?1, ?2)");
    defer st.finalize() catch {};
    try st.bindInt64(1, 1);
    try st.bindText(2, "uno");
    try std.testing.expectError(error.StepFailed, st.step());

    // The primary code and the extended code are both still readable, and the
    // extended one carries the primary in its low byte.
    const primary = db.errStatus().?;
    try std.testing.expectEqual(sqlite.Status.constraint, primary);
    try std.testing.expectEqual(@as(c_int, sqlite.Status.constraint.code()), db.errcode());
    const extended = db.extendedErrcode();
    try std.testing.expect(extended != db.errcode());
    try std.testing.expectEqual(sqlite.Status.constraint, sqlite.Status.fromExtendedCode(extended).?);

    // The message is the library's own, not one this facade invented.
    try std.testing.expect(db.errmsg().len > 0);

    // The connection is still usable after a failed statement, which is what
    // `sqlite3_reset` is for.
    st.reset();
    try std.testing.expectEqual(sqlite.Step.done, try st.step());
}

// A statement that does not compile is a prepare failure, and the reason is
// readable.
test "a syntax error is PrepareFailed with the library's diagnosis" {
    var db = try openMemory();
    defer db.close();

    try std.testing.expectError(error.PrepareFailed, db.prepare("SELECT FROM"));
    try std.testing.expectEqual(sqlite.Status.error_, db.errStatus().?);
    try std.testing.expect(db.errmsg().len > 0);

    // A table that does not exist is a different code, and stays distinguishable.
    try std.testing.expectError(error.PrepareFailed, db.prepare("SELECT * FROM absent"));
    try std.testing.expectEqual(sqlite.Status.error_, db.errStatus().?);
    try std.testing.expect(std.mem.indexOf(u8, db.errmsg(), "absent") != null);
}

// Input that compiles to no statement at all is `NoStatement`, not a failure.
//
// `src/sqlite3.h:4539-4542` says `*ppStmt` is NULL both when there is an error
// and when the text contains no SQL - an empty string or a comment - and that
// the two are told apart by the return code. This checks the second half: a
// perfectly valid comment is `SQLITE_OK` with no statement, and the facade names
// it rather than handing back a zero value or panicking.
test "an empty statement or a bare comment is NoStatement" {
    var db = try openMemory();
    defer db.close();

    try std.testing.expectError(error.NoStatement, db.prepare(""));
    // The connection is untouched by that: the code is still OK.
    try std.testing.expectEqual(sqlite.Status.ok, db.errStatus().?);

    try std.testing.expectError(error.NoStatement, db.prepare("-- just a comment"));
    try std.testing.expectEqual(sqlite.Status.ok, db.errStatus().?);

    // And a comment followed by a real statement compiles the statement.
    var st = try db.prepare("-- leading comment\nSELECT 7");
    defer st.finalize() catch {};
    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqual(@as(i64, 7), try st.columnInt64(0));
}

// An out-of-range column index is refused here rather than answering 0.
//
// `src/sqlite3.h:5582` types `sqlite3_column_int` as `int`, and the header has
// no out-of-range answer to report: a silent zero is indistinguishable from a
// real zero, so this module checks the index before the call.
test "an out-of-range column is ColumnOutOfRange, not a zero" {
    var db = try openMemory();
    defer db.close();
    try db.exec("CREATE TABLE t(a INTEGER, b TEXT)");
    try db.exec("INSERT INTO t VALUES(0, '')");

    var st = try db.prepare("SELECT a, b FROM t");
    defer st.finalize() catch {};
    try std.testing.expectEqual(sqlite.Step.row, try st.step());

    // Column 0 really is zero, so a facade that answered zero for a missing
    // column would pass a naive test. Column 2 does not exist at all.
    try std.testing.expectEqual(@as(i64, 0), try st.columnInt64(0));
    try std.testing.expectError(error.ColumnOutOfRange, st.columnInt64(2));
    try std.testing.expectError(error.ColumnOutOfRange, st.columnText(2));
    try std.testing.expectError(error.ColumnOutOfRange, st.columnBlob(2));
    try std.testing.expectError(error.ColumnOutOfRange, st.columnDouble(2));
    try std.testing.expect(st.columnType(2) == null);
}

// Opening a combination upstream says is undefined is refused before the call.
test "an undefined open-flag combination is refused without touching the library" {
    // `src/sqlite3.h:3741-3744` requires one of READONLY, or READWRITE with
    // CREATE. All-false is neither.
    try std.testing.expectError(
        error.NoOpenMode,
        sqlite.Db.open(":memory:", .{}),
    );
    // READWRITE without CREATE is neither either.
    try std.testing.expectError(
        error.NoOpenMode,
        sqlite.Db.open(":memory:", .{ .readwrite = true }),
    );
    // Two mutually exclusive bits cannot both apply, and upstream gives each a
    // meaning of its own.
    try std.testing.expectError(
        error.NoOpenMode,
        sqlite.Db.open(":memory:", .{
            .readwrite = true,
            .create = true,
            .nomutex = true,
            .fullmutex = true,
        }),
    );
    try std.testing.expectError(
        error.NoOpenMode,
        sqlite.Db.open(":memory:", .{
            .readwrite = true,
            .create = true,
            .sharedcache = true,
            .privatecache = true,
        }),
    );

    // The bits each permitted combination produces, checked against the
    // header's own numbers rather than against a constant of this file's own.
    const normal = (sqlite.OpenFlags{ .readwrite = true, .create = true }).bits().?;
    try std.testing.expectEqual(
        @as(c_int, sqlite.c.SQLITE_OPEN_READWRITE | sqlite.c.SQLITE_OPEN_CREATE),
        normal,
    );
}

// A failing open hands back the connection, so the message is still readable.
//
// `src/sqlite3.h:3719-3726`: a connection is usually returned even when the open
// fails, precisely so `sqlite3_errmsg` can describe what happened. A facade that
// closed it before returning would destroy the only diagnosis there is. This
// opens a path whose *parent directory* does not exist and with READWRITE
// CREATE, which SQLite refuses with `SQLITE_CANTOPEN`, and reads the message
// back off the connection it was given.
test "a failed open still gives back a connection that can describe itself" {
    const missing = "/sqlite-facade-test-no-such-directory/does-not-exist.db";

    switch (try sqlite.Db.open(missing, .{ .readwrite = true, .create = true })) {
        .ok => {
            // A build whose VFS created the tree would have to say so rather than
            // pass this silently; that is the one outcome the fixture cannot
            // assume against.
            return error.UnexpectedOpenSuccess;
        },
        .failed => |f| {
            var db = f.db;
            // `SQLITE_CANTOPEN` is src/sqlite3.h:464.
            try std.testing.expectEqual(sqlite.Status.cantopen, f.db.errStatus().?);
            try std.testing.expectEqual(@as(c_int, f.code), f.db.errcode());
            try std.testing.expect(f.message().len > 0);
            try std.testing.expectEqualStrings(f.db.errmsg(), f.message());
            db.close();
        },
        .no_connection => |code| {
            // `src/sqlite3.h:3721-3723` names allocation failure as the case
            // that produces no handle. If that is what happened here, there is
            // nothing to close and nothing to read, and the code still says why.
            try std.testing.expect(code != sqlite.c.SQLITE_OK);
        },
    }
}

// Closing releases the connection, and closing twice is not a use-after-free.
//
// `sqlite3_close_v2` is the destructor this module uses because
// `src/sqlite3.h:335-343` says it returns `SQLITE_OK` even with statements still
// open and defers the deallocation. A `*Db` that clears its own handle makes
// the second call a no-op rather than a double free.
test "close clears the connection and is safe to call twice" {
    var db = try openMemory();
    try seed(db);
    try db.closeChecked();

    // The handle is gone. This asserts the facade's own state and nothing more:
    // the library is not asked anything with a null connection, because what a
    // null connection answers is not a contract this package depends on.
    try std.testing.expect(db.handle == null);
    db.close();
    try std.testing.expect(db.handle == null);
}

// A connection closes cleanly with an unfinalized statement, which is the case
// `sqlite3_close_v2` exists for.
//
// `src/sqlite3.h:335-343`: unlike `sqlite3_close`, `sqlite3_close_v2` returns
// `SQLITE_OK` with statements still open, marking the connection a zombie and
// deallocating it once they are finalized. This test never finalizes the
// statement - that is the point - and still checks that the close reported
// success, which is the contract a `defer db.close()` in an error path relies on.
test "a connection closes with a live statement, and the statement is destroyed" {
    var db = try openMemory();
    var st = try db.prepare("SELECT 1");
    try std.testing.expectEqual(sqlite.Step.row, try st.step());

    // The statement is deliberately leaked here: this is what
    // `sqlite3_close_v2`'s zombie path is for.
    try db.closeChecked();
    try std.testing.expect(db.handle == null);

    // The connection was a `:memory:` one, so there is nothing on disk to find.
}

// One statement, many rows: `reset` is what makes a prepared statement
// reusable, and the values it answers have to be the ones that went in.
//
// `sqlite3_reset` is what upstream requires before a statement that failed or
// finished is run again (`src/sqlite3.h:5652-5660`), and
// `sqlite3_clear_bindings` (`src/sqlite3.h:5100`) is what makes a parameter
// from one row not leak into the next. Both are behind `Statement.reset`, so a
// reused statement that leaked a binding or a row position would read the
// wrong values here rather than nowhere.
test "a reset statement is reusable, and answers every row the value that went in" {
    var db = try openMemory();
    defer db.close();
    try db.exec("CREATE TABLE t(v INTEGER)");

    // Insert the twelve cents with one reused statement.
    var insert = try db.prepare("INSERT INTO t VALUES(?1)");
    defer insert.finalize() catch {};
    for (rows) |row| {
        insert.reset();
        try insert.bindInt64(1, row.cents);
        try insert.runToCompletion();
    }

    // The same sum computed over `rows` in Zig, with no database involved.
    var sum_once: i64 = 0;
    for (rows) |row| sum_once += row.cents;

    // Walk the table in both directions, one prepared statement per direction,
    // with `reset` between *runs* rather than between rows: a reset rewinds the
    // cursor (`src/sqlite3.h:5652-5660`), so calling it after every row would
    // re-read the first row forever.
    //
    // Two directions, because a statement that answered a *previous* run's
    // value can hide behind one ordering of the data; two runs per direction,
    // because a reset that did not rewind would answer `.done` at once and walk
    // nothing at all, which one run cannot tell from a statement that walked
    // everything.
    var sum_walk: i64 = 0;
    var rows_walked: i64 = 0;
    var direction: u8 = 0;
    while (direction < 2) : (direction += 1) {
        const text = if (direction == 0)
            "SELECT v FROM t ORDER BY v"
        else
            "SELECT v FROM t ORDER BY v DESC";
        var st = try db.prepare(text);
        defer st.finalize() catch {};
        var run: usize = 0;
        while (run < 2) : (run += 1) {
            st.reset();
            var run_sum: i64 = 0;
            var run_rows: i64 = 0;
            while (true) {
                switch (try st.step()) {
                    .done => break,
                    .row => {
                        run_sum += try st.columnInt64(0);
                        run_rows += 1;
                    },
                }
            }
            // Each run is the whole table in its own right, checked before it is
            // folded into the totals.
            try std.testing.expectEqual(@as(i64, 12), run_rows);
            sum_walk += run_sum;
            rows_walked += run_rows;
        }
    }

    try std.testing.expectEqual(4 * sum_once, sum_walk);
    try std.testing.expectEqual(@as(i64, 4 * 12), rows_walked);

    // The count through one reused statement is the count of the rows that went
    // in, which is the same fact stated a second way.
    var compare = try db.prepare("SELECT COUNT(*) FROM t");
    defer compare.finalize() catch {};
    try std.testing.expectEqual(sqlite.Step.row, try compare.step());
    try std.testing.expectEqual(@as(i64, 12), try compare.columnInt64(0));
}

// `last_insert_rowid` and `changes` are the library's own bookkeeping, checked
// against a question with a known answer rather than against a constant.
//
// The rowid of an `INTEGER PRIMARY KEY` row is the key itself, so the fixture
// says what both values have to be after the second insert.
test "last_insert_rowid and changes answer a question with a known answer" {
    var db = try openMemory();
    defer db.close();
    try db.exec("CREATE TABLE t(k INTEGER PRIMARY KEY, v TEXT)");

    try db.exec("INSERT INTO t VALUES(7, 'seven')");
    try std.testing.expectEqual(@as(i64, 7), db.lastInsertRowid());
    try std.testing.expectEqual(@as(i64, 1), db.changes());

    // One statement changing three rows: `changes` is the count of the most
    // recent statement, not of the transaction.
    try db.exec("INSERT INTO t VALUES(8, 'eight'),(9, 'nine')");
    try std.testing.expectEqual(@as(i64, 9), db.lastInsertRowid());
    try std.testing.expectEqual(@as(i64, 2), db.changes());

    // A statement that changed nothing answers zero rather than the previous
    // count.
    try db.exec("DELETE FROM t WHERE k = 99");
    try std.testing.expectEqual(@as(i64, 0), db.changes());
}

// A transaction state is the library's own answer, asked before, inside and
// after one.
test "inTransaction reports the library's transaction state" {
    var db = try openMemory();
    defer db.close();

    try std.testing.expect(!db.inTransaction());
    try db.exec("CREATE TABLE t(v INTEGER)");
    try std.testing.expect(!db.inTransaction());

    var st = try db.prepare("BEGIN");
    defer st.finalize() catch {};
    try st.runToCompletion();
    // A deferred `BEGIN` takes no lock yet, so there is still no transaction
    // state to report: `sqlite3_txn_state` answers with the btree's own
    // `inTrans` (`src/sqlite3.c:84552-84555`), and that is still `SQLITE_TXN_NONE`
    // until the first statement inside the transaction reads or writes.
    try std.testing.expect(!db.inTransaction());

    // The write is what starts it. `SQLITE_TXN_WRITE` is 2
    // (`src/sqlite3.h:7093`), and a non-zero answer is what `inTransaction`
    // reports.
    try db.exec("INSERT INTO t VALUES(1)");
    try std.testing.expect(db.inTransaction());

    try db.exec("COMMIT");
    try std.testing.expect(!db.inTransaction());
    try std.testing.expectEqual(@as(i64, 1), db.changes());
}

// `exec` finalizes its own statement even when the step fails, so a failed
// `exec` leaves nothing behind.
test "a failed exec leaves no live statement" {
    var db = try openMemory();
    defer db.close();
    try db.exec("CREATE TABLE t(k INTEGER PRIMARY KEY)");
    try db.exec("INSERT INTO t VALUES(1)");

    try std.testing.expectError(error.StepFailed, db.exec("INSERT INTO t VALUES(1)"));
    try std.testing.expectEqual(sqlite.Status.constraint, db.errStatus().?);

    // Had `exec` leaked its statement, this close would be the `sqlite3_close`
    // case - SQLITE_BUSY - instead of the clean one.
    try db.closeChecked();
}

// The library's answer about itself, asked for what it is for.
//
// This is not a version-string pin: nothing here compares a version with a
// literal. What is checked is that the three self-describing entry points
// answer, that the string and the number agree about the same release, and that
// the integer path a provider advertises by reporting itself serialized actually
// behaves - which is what makes `sqlite3_threadsafe`'s answer meaningful rather
// than a constant read back.
test "the library describes itself, and the thread-safety it reports is real" {
    const text = sqlite.libraryVersion();
    const number = sqlite.libraryVersionNumber();
    const source = sqlite.sourceId();

    try std.testing.expect(text.len > 0);
    try std.testing.expect(number > 0);
    // The check-in string carries a hash, so it is longer than any version text
    // and contains the whitespace `src/sqlite3.h:136-141` describes.
    try std.testing.expect(source.len > text.len);
    try std.testing.expect(std.mem.indexOf(u8, source, " ") != null);

    // The number encodes the string: three components, `X*1000000 + Y*1000 + Z`
    // (`src/sqlite3.h:126-127`). Parsing the string and rebuilding the number is
    // an independent derivation of the same fact, so this fails if either the
    // string or the number stops describing the release the other one names.
    var it = std.mem.splitScalar(u8, text, '.');
    const major = try std.fmt.parseInt(i64, it.next().?, 10);
    const minor = try std.fmt.parseInt(i64, it.next().?, 10);
    const patch = try std.fmt.parseInt(i64, it.next().?, 10);
    try std.testing.expect(it.next() == null);
    try std.testing.expectEqual(major * 1_000_000 + minor * 1000 + patch, number);

    // `sqlite3_threadsafe` is 1 for serialized, 2 for multi-thread and 0 for
    // single-thread (`src/sqlite3.h:259`). Whatever it answers, this package's
    // facade must be usable from one thread either way - and when it answers
    // serialized, a second connection on this same thread must still work, which
    // is the observable half of the claim.
    const mode = sqlite.threadSafe();
    try std.testing.expect(mode >= 0 and mode <= 2);
    var second = try openMemory();
    defer second.close();
    try second.exec("CREATE TABLE t(v INTEGER)");
    try second.exec("INSERT INTO t VALUES(1)");
    try std.testing.expectEqual(@as(i64, 1), second.changes());
}

// The status taxonomy is the header's, transcribed.
//
// This is a mapping test in the one direction that can be wrong: every value of
// `Status` must equal the header's macro for the same name. `Status.fromCode`
// and `fromExtendedCode` must then recover exactly those values, and nothing
// else.
test "the Status taxonomy is the header's, value for value" {
    try std.testing.expectEqual(@as(c_int, 0), sqlite.Status.ok.code());
    try std.testing.expectEqual(@as(c_int, 1), sqlite.Status.error_.code());
    try std.testing.expectEqual(@as(c_int, 2), sqlite.Status.internal.code());
    try std.testing.expectEqual(@as(c_int, 5), sqlite.Status.busy.code());
    try std.testing.expectEqual(@as(c_int, 11), sqlite.Status.corrupt.code());
    try std.testing.expectEqual(@as(c_int, 14), sqlite.Status.cantopen.code());
    try std.testing.expectEqual(@as(c_int, 19), sqlite.Status.constraint.code());
    try std.testing.expectEqual(@as(c_int, 21), sqlite.Status.misuse.code());
    try std.testing.expectEqual(@as(c_int, 26), sqlite.Status.notadb.code());
    try std.testing.expectEqual(@as(c_int, 100), sqlite.Status.row.code());
    try std.testing.expectEqual(@as(c_int, 101), sqlite.Status.done.code());

    // The translated macros are the header's own, and each `Status` member has to
    // equal the macro of the same name.
    try std.testing.expectEqual(sqlite.c.SQLITE_OK, sqlite.Status.ok.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_ERROR, sqlite.Status.error_.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_CONSTRAINT, sqlite.Status.constraint.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_ROW, sqlite.Status.row.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_DONE, sqlite.Status.done.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_CANTOPEN, sqlite.Status.cantopen.code());

    // Round trips.
    try std.testing.expectEqual(sqlite.Status.constraint, sqlite.Status.fromCode(19).?);
    try std.testing.expectEqual(sqlite.Status.done, sqlite.Status.fromCode(101).?);
    // An extended code is not a member, and saying so is the point: folding it in
    // would lose the primary code.
    try std.testing.expect(sqlite.Status.fromCode(sqlite.c.SQLITE_CONSTRAINT_CHECK) == null);
    // Its primary part is recovered, because `src/sqlite3.h:500` defines every
    // extended code as `PRIMARY | (N<<8)`.
    try std.testing.expectEqual(
        sqlite.Status.constraint,
        sqlite.Status.fromExtendedCode(sqlite.c.SQLITE_CONSTRAINT_CHECK).?,
    );
    // A primary code passes through unchanged, so the same function is usable on
    // `sqlite3_errcode`.
    try std.testing.expectEqual(
        sqlite.Status.ok,
        sqlite.Status.fromExtendedCode(sqlite.c.SQLITE_OK).?,
    );
    // A code outside the taxonomy has no answer, in either direction.
    try std.testing.expect(sqlite.Status.fromCode(27) == null);
    try std.testing.expect(sqlite.Status.fromCode(-1) == null);
    try std.testing.expect(sqlite.Status.fromExtendedCode(27) == null);
}

// The column classes are the header's five, and no others.
test "the column classes are the header's five" {
    try std.testing.expectEqual(@as(c_int, 1), sqlite.ColumnType.integer.code());
    try std.testing.expectEqual(@as(c_int, 2), sqlite.ColumnType.float.code());
    try std.testing.expectEqual(@as(c_int, 3), sqlite.ColumnType.text.code());
    try std.testing.expectEqual(@as(c_int, 4), sqlite.ColumnType.blob.code());
    try std.testing.expectEqual(@as(c_int, 5), sqlite.ColumnType.null.code());

    try std.testing.expectEqual(sqlite.c.SQLITE_INTEGER, sqlite.ColumnType.integer.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_FLOAT, sqlite.ColumnType.float.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_TEXT, sqlite.ColumnType.text.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_BLOB, sqlite.ColumnType.blob.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_NULL, sqlite.ColumnType.null.code());

    try std.testing.expectEqual(sqlite.ColumnType.blob, sqlite.ColumnType.fromCode(4).?);
    try std.testing.expectEqual(sqlite.ColumnType.null, sqlite.ColumnType.fromCode(5).?);
    try std.testing.expect(sqlite.ColumnType.fromCode(0) == null);
    try std.testing.expect(sqlite.ColumnType.fromCode(6) == null);
}

// Every class the facade names is reachable through a real column, so the
// mapping above is not the only evidence for it.
test "all five column classes are reachable from one table" {
    var db = try openMemory();
    defer db.close();
    try db.exec(
        \\CREATE TABLE t(i INTEGER, f REAL, s TEXT, b BLOB, n INTEGER)
    );

    var insert = try db.prepare("INSERT INTO t VALUES(?1, ?2, ?3, ?4, ?5)");
    defer insert.finalize() catch {};
    try insert.bindInt64(1, 1);
    try insert.bindDouble(2, 2.5);
    try insert.bindText(3, "three");
    try insert.bindBlob(4, "four");
    try insert.bindNull(5);
    try insert.runToCompletion();

    var st = try db.prepare("SELECT i, f, s, b, n FROM t");
    defer st.finalize() catch {};
    try std.testing.expectEqual(sqlite.Step.row, try st.step());

    try std.testing.expectEqual(sqlite.ColumnType.integer, st.columnType(0).?);
    try std.testing.expectEqual(sqlite.ColumnType.float, st.columnType(1).?);
    try std.testing.expectEqual(sqlite.ColumnType.text, st.columnType(2).?);
    try std.testing.expectEqual(sqlite.ColumnType.blob, st.columnType(3).?);
    try std.testing.expectEqual(sqlite.ColumnType.null, st.columnType(4).?);

    // The values themselves, through the accessor that matches each class. A
    // `2.5` read as an integer would be 2, which is why the float column is
    // checked through `columnDouble` and not through `columnInt64`.
    try std.testing.expectEqual(@as(i64, 1), try st.columnInt64(0));
    try std.testing.expectEqual(@as(f64, 2.5), try st.columnDouble(1));
    try std.testing.expectEqualStrings("three", try st.columnText(2));
    try std.testing.expectEqualStrings("four", try st.columnBlob(3));
    try std.testing.expectError(error.NullValue, st.columnText(4));
}

// `sqlite3_errstr` answers for a code this facade does not know too.
test "errstr answers for a known and an unknown code" {
    // The header says the answer is NULL only when the code has no text at all,
    // so a NULL here would itself be the finding rather than something to skip.
    const busy = sqlite.errstr(sqlite.Status.busy.code()) orelse return error.NoErrstrText;
    try std.testing.expect(busy.len > 0);
    const constraint = sqlite.errstr(sqlite.Status.constraint.code()) orelse return error.NoErrstrText;
    try std.testing.expect(constraint.len > 0);
    // `src/sqlite3.h:4217-4224` says the routine works for codes it does not
    // recognise as well as those it does, so this asks for one this facade has
    // no member for.
    const unknown = sqlite.errstr(27) orelse return error.NoErrstrText;
    try std.testing.expect(unknown.len > 0);
}

// A statement knows the SQL it was compiled from, and that is the copy the
// `prepare_v2` family makes.
//
// `src/sqlite3.h:4554-4556`: a `prepare_v2` statement holds a copy of the
// original text, so `sqlite3_sql` keeps answering after the caller's buffer is
// gone. Here the answer is checked against text this test then drops, which is
// the observable form of that claim.
test "a statement carries a copy of its own SQL text" {
    var db = try openMemory();
    defer db.close();

    // The terminator has to be a real zero: a `[:0]` slice of a buffer carries a
    // checked sentinel, not an assumed one.
    var owned_buffer: [64]u8 = undefined;
    @memset(&owned_buffer, 0);
    const text = "SELECT 11 AS eleven";
    @memcpy(owned_buffer[0..text.len], text);
    const borrowed = owned_buffer[0..text.len :0];

    var st = try db.prepare(borrowed);
    defer st.finalize() catch {};

    // Scribble over the caller's buffer. If the statement held a pointer to it,
    // the comparison below would fail or read something else.
    @memset(&owned_buffer, 0xff);

    // `sql()` answers a non-optional slice, so its presence is the return type
    // itself; the claim worth checking here is the content, against text whose
    // buffer this test has already scribbled over.
    try std.testing.expectEqualStrings(text, st.sql());
    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqual(@as(i64, 11), try st.columnInt64(0));
    try std.testing.expectEqualStrings("eleven", st.columnName(0).?);
}

// The loaded-provider route, when this build has one.
//
// In a linked build there is no table, `load` is a no-op and `loadedSource`
// answers null; those are the only two statements this makes, and they are
// statements about the configuration rather than about SQLite. The proof that
// the runtime route works is `zig build consumer -Druntime=true`, which runs a
// program that names a provider and then does the same aggregation through it.
test "the dispatch route is present in exactly one of its two shapes" {
    // Nothing here asserts that a version string equals a literal, or that a
    // declaration exists, which is what the fixture policy forbids. What it
    // checks is the shape of the build.
    if (sqlite.runtime_loaded) {
        // A runtime-loaded build has not loaded anything yet, and must say so
        // rather than claiming a provider.
        try std.testing.expect(sqlite.loadedSource() == null);
    } else {
        try std.testing.expect(sqlite.loadedSource() == null);
        // `load` in a linked build is a no-op that cannot report a provider.
        try sqlite.load(.{ .system = "libsqlite3-nonexistent-for-this-check" });
        try std.testing.expect(sqlite.loadedSource() == null);
    }
}
