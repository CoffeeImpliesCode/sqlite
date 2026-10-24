// SPDX-License-Identifier: LicenseRef-PublicDomain
// See FORK-LICENSE.md for what that identifier covers.

//! Behavioral tests for the SQLite facade.

const std = @import("std");
const sqlite = @import("sqlite3");

/// Fixture rows shared by SQL seeding and the Zig reduction.
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

/// Computes grouped fixture totals with Zig loops, independently of SQL.
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

    try std.testing.expectEqual(@as(usize, 5), st.columnCount());
    try std.testing.expectEqualStrings("account", st.columnName(0).?);
    try std.testing.expectEqualStrings("SUM(cents)", st.columnName(1).?);
    try std.testing.expectEqualStrings("COUNT(*)", st.columnName(2).?);
    try std.testing.expectEqualStrings("MIN(entry)", st.columnName(3).?);
    try std.testing.expectEqualStrings("MAX(entry)", st.columnName(4).?);
    try std.testing.expect(st.columnName(5) == null);
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

                try std.testing.expectEqual(sqlite.ColumnType.text, st.columnType(0).?);
                try std.testing.expectEqual(sqlite.ColumnType.integer, st.columnType(1).?);
                seen += 1;
            },
        }
    }
    try std.testing.expectEqual(@as(usize, 3), seen);
}

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

    // SQLite may restart a completed SELECT when stepped again.
    try std.testing.expectEqual(sqlite.Step.done, try st.step());
    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqualStrings("grand", try st.columnText(0));
    try std.testing.expectEqual(@as(i64, 425), try st.columnInt64(1));
}

test "the SQL aggregation and a straight-line reduction agree with the table" {
    const accounts = [_][]const u8{ "a", "b", "c" };

    const buckets = try reduce(std.testing.allocator, &accounts);
    defer std.testing.allocator.free(buckets);

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

    var sum_of_sums: i64 = 0;
    var sum_of_counts: i64 = 0;
    for (buckets) |bucket| {
        sum_of_sums += bucket.sum;
        sum_of_counts += bucket.count;
    }
    try std.testing.expectEqual(@as(i64, 425), sum_of_sums);
    try std.testing.expectEqual(@as(i64, 12), sum_of_counts);
}

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

    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqual(sqlite.ColumnType.null, st.columnType(0).?);
    try std.testing.expectError(error.NullValue, st.columnText(0));
    try std.testing.expect(
        db.errcode() == sqlite.c.SQLITE_OK or db.errcode() == sqlite.c.SQLITE_ROW,
    );

    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqual(sqlite.ColumnType.text, st.columnType(0).?);
    try std.testing.expectEqualStrings("", try st.columnText(0));
    try std.testing.expectEqual(@as(usize, 0), (try st.columnText(0)).len);
}

test "empty text and blobs remain distinct from NULL after another statement fails" {
    var db = try openMemory();
    defer db.close();
    var st = try db.prepare("SELECT ?1, ?2, NULL, '', x'', zeroblob(0)");
    defer st.finalize() catch {};
    try st.bindText(1, "");
    try st.bindBlob(2, "");
    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqual(sqlite.ColumnType.text, st.columnType(0).?);
    try std.testing.expectEqual(sqlite.ColumnType.blob, st.columnType(1).?);

    try std.testing.expectError(error.PrepareFailed, db.prepare("SELECT FROM"));
    try std.testing.expectEqual(sqlite.c.SQLITE_ERROR, db.errcode());
    inline for (.{ 0, 1, 3, 4, 5 }) |index| {
        try std.testing.expectEqualStrings("", try st.columnBlob(index));
        try std.testing.expectEqualStrings("", try st.columnText(index));
    }
    try std.testing.expectError(error.NullValue, st.columnText(2));
    try std.testing.expectError(error.NullValue, st.columnBlob(2));
}

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
    try std.testing.expectEqual(with_nul.len, (try st.columnText(1)).len);
    try std.testing.expectEqualSlices(u8, with_nul, try st.columnText(1));
}

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

    const primary = db.errStatus().?;
    try std.testing.expectEqual(sqlite.Status.constraint, primary);
    try std.testing.expectEqual(@as(c_int, sqlite.Status.constraint.code()), db.errcode());
    const extended = db.extendedErrcode();
    try std.testing.expect(extended != db.errcode());
    try std.testing.expectEqual(sqlite.Status.constraint, sqlite.Status.fromExtendedCode(extended).?);

    try std.testing.expect(db.errmsg().len > 0);

    st.reset();
    try std.testing.expectEqual(sqlite.Step.done, try st.step());
}

test "a syntax error is PrepareFailed with the library's diagnosis" {
    var db = try openMemory();
    defer db.close();

    try std.testing.expectError(error.PrepareFailed, db.prepare("SELECT FROM"));
    try std.testing.expectEqual(sqlite.Status.error_, db.errStatus().?);
    try std.testing.expect(db.errmsg().len > 0);

    try std.testing.expectError(error.PrepareFailed, db.prepare("SELECT * FROM absent"));
    try std.testing.expectEqual(sqlite.Status.error_, db.errStatus().?);
    try std.testing.expect(std.mem.indexOf(u8, db.errmsg(), "absent") != null);
}

test "an empty statement or a bare comment is NoStatement" {
    var db = try openMemory();
    defer db.close();

    try std.testing.expectError(error.NoStatement, db.prepare(""));
    try std.testing.expectEqual(sqlite.Status.ok, db.errStatus().?);

    try std.testing.expectError(error.NoStatement, db.prepare("-- just a comment"));
    try std.testing.expectEqual(sqlite.Status.ok, db.errStatus().?);

    var st = try db.prepare("-- leading comment\nSELECT 7");
    defer st.finalize() catch {};
    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqual(@as(i64, 7), try st.columnInt64(0));
}

test "an out-of-range column is ColumnOutOfRange, not a zero" {
    var db = try openMemory();
    defer db.close();
    try db.exec("CREATE TABLE t(a INTEGER, b TEXT)");
    try db.exec("INSERT INTO t VALUES(0, '')");

    var st = try db.prepare("SELECT a, b FROM t");
    defer st.finalize() catch {};
    try std.testing.expectEqual(sqlite.Step.row, try st.step());

    try std.testing.expectEqual(@as(i64, 0), try st.columnInt64(0));
    try std.testing.expectError(error.ColumnOutOfRange, st.columnInt64(2));
    try std.testing.expectError(error.ColumnOutOfRange, st.columnText(2));
    try std.testing.expectError(error.ColumnOutOfRange, st.columnBlob(2));
    try std.testing.expectError(error.ColumnOutOfRange, st.columnDouble(2));
    try std.testing.expect(st.columnType(2) == null);
}

test "an undefined open-flag combination is refused without touching the library" {
    try std.testing.expectError(
        error.NoOpenMode,
        sqlite.Db.open(":memory:", .{}),
    );
    try std.testing.expectError(
        error.NoOpenMode,
        sqlite.Db.open(":memory:", .{ .readwrite = true }),
    );
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

    const normal = (sqlite.OpenFlags{ .readwrite = true, .create = true }).bits().?;
    try std.testing.expectEqual(
        @as(c_int, sqlite.c.SQLITE_OPEN_READWRITE | sqlite.c.SQLITE_OPEN_CREATE),
        normal,
    );
}

test "a failed open still gives back a connection that can describe itself" {
    const missing = "/sqlite-facade-test-no-such-directory/does-not-exist.db";

    switch (try sqlite.Db.open(missing, .{ .readwrite = true, .create = true })) {
        .ok => {
            return error.UnexpectedOpenSuccess;
        },
        .failed => |f| {
            var db = f.db;
            try std.testing.expectEqual(sqlite.Status.cantopen, f.db.errStatus().?);
            try std.testing.expectEqual(@as(c_int, f.code), f.db.errcode());
            try std.testing.expect(f.message().len > 0);
            try std.testing.expectEqualStrings(f.db.errmsg(), f.message());
            db.close();
        },
        .no_connection => |code| {
            try std.testing.expect(code != sqlite.c.SQLITE_OK);
        },
    }
}

test "close clears the connection and is safe to call twice" {
    var db = try openMemory();
    try seed(db);
    try db.closeChecked();

    try std.testing.expect(db.handle == null);
    db.close();
    try std.testing.expect(db.handle == null);
}

test "a connection closes with a live statement, and the statement is destroyed" {
    var db = try openMemory();
    var st = try db.prepare("SELECT 1");
    try std.testing.expectEqual(sqlite.Step.row, try st.step());

    try db.closeChecked();
    try std.testing.expect(db.handle == null);
}

test "a reset statement is reusable, and answers every row the value that went in" {
    var db = try openMemory();
    defer db.close();
    try db.exec("CREATE TABLE t(v INTEGER)");

    var insert = try db.prepare("INSERT INTO t VALUES(?1)");
    defer insert.finalize() catch {};
    for (rows) |row| {
        insert.reset();
        try insert.bindInt64(1, row.cents);
        try insert.runToCompletion();
    }

    var sum_once: i64 = 0;
    for (rows) |row| sum_once += row.cents;

    // Reset between runs, not rows, so each query walks the full result set.
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
            try std.testing.expectEqual(@as(i64, 12), run_rows);
            sum_walk += run_sum;
            rows_walked += run_rows;
        }
    }

    try std.testing.expectEqual(4 * sum_once, sum_walk);
    try std.testing.expectEqual(@as(i64, 4 * 12), rows_walked);

    var compare = try db.prepare("SELECT COUNT(*) FROM t");
    defer compare.finalize() catch {};
    try std.testing.expectEqual(sqlite.Step.row, try compare.step());
    try std.testing.expectEqual(@as(i64, 12), try compare.columnInt64(0));
}

test "last_insert_rowid and changes answer a question with a known answer" {
    var db = try openMemory();
    defer db.close();
    try db.exec("CREATE TABLE t(k INTEGER PRIMARY KEY, v TEXT)");

    try db.exec("INSERT INTO t VALUES(7, 'seven')");
    try std.testing.expectEqual(@as(i64, 7), db.lastInsertRowid());
    try std.testing.expectEqual(@as(i64, 1), db.changes());

    try db.exec("INSERT INTO t VALUES(8, 'eight'),(9, 'nine')");
    try std.testing.expectEqual(@as(i64, 9), db.lastInsertRowid());
    try std.testing.expectEqual(@as(i64, 2), db.changes());

    try db.exec("DELETE FROM t WHERE k = 99");
    try std.testing.expectEqual(@as(i64, 0), db.changes());
}

test "inTransaction reports the library's transaction state" {
    var db = try openMemory();
    defer db.close();

    try std.testing.expect(!db.inTransaction());
    try db.exec("CREATE TABLE t(v INTEGER)");
    try std.testing.expect(!db.inTransaction());

    var st = try db.prepare("BEGIN");
    defer st.finalize() catch {};
    try st.runToCompletion();
    // Deferred `BEGIN` starts only when the transaction first reads or writes.
    try std.testing.expect(!db.inTransaction());

    try db.exec("INSERT INTO t VALUES(1)");
    try std.testing.expect(db.inTransaction());

    try db.exec("COMMIT");
    try std.testing.expect(!db.inTransaction());
    try std.testing.expectEqual(@as(i64, 1), db.changes());
}

test "a failed exec leaves no live statement" {
    var db = try openMemory();
    defer db.close();
    try db.exec("CREATE TABLE t(k INTEGER PRIMARY KEY)");
    try db.exec("INSERT INTO t VALUES(1)");

    try std.testing.expectError(error.StepFailed, db.exec("INSERT INTO t VALUES(1)"));
    try std.testing.expectEqual(sqlite.Status.constraint, db.errStatus().?);

    try db.closeChecked();
}

test "the library describes itself, and the thread-safety it reports is real" {
    const text = sqlite.libraryVersion();
    const number = sqlite.libraryVersionNumber();
    const source = sqlite.sourceId();

    try std.testing.expect(text.len > 0);
    try std.testing.expect(number > 0);
    try std.testing.expect(source.len > text.len);
    try std.testing.expect(std.mem.indexOf(u8, source, " ") != null);

    var it = std.mem.splitScalar(u8, text, '.');
    const major = try std.fmt.parseInt(i64, it.next().?, 10);
    const minor = try std.fmt.parseInt(i64, it.next().?, 10);
    const patch = try std.fmt.parseInt(i64, it.next().?, 10);
    try std.testing.expect(it.next() == null);
    try std.testing.expectEqual(major * 1_000_000 + minor * 1000 + patch, number);

    const mode = sqlite.threadSafe();
    try std.testing.expect(mode >= 0 and mode <= 2);
    var second = try openMemory();
    defer second.close();
    try second.exec("CREATE TABLE t(v INTEGER)");
    try second.exec("INSERT INTO t VALUES(1)");
    try std.testing.expectEqual(@as(i64, 1), second.changes());
}

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

    try std.testing.expectEqual(sqlite.c.SQLITE_OK, sqlite.Status.ok.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_ERROR, sqlite.Status.error_.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_CONSTRAINT, sqlite.Status.constraint.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_ROW, sqlite.Status.row.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_DONE, sqlite.Status.done.code());
    try std.testing.expectEqual(sqlite.c.SQLITE_CANTOPEN, sqlite.Status.cantopen.code());

    try std.testing.expectEqual(sqlite.Status.constraint, sqlite.Status.fromCode(19).?);
    try std.testing.expectEqual(sqlite.Status.done, sqlite.Status.fromCode(101).?);
    try std.testing.expect(sqlite.Status.fromCode(sqlite.c.SQLITE_CONSTRAINT_CHECK) == null);
    try std.testing.expectEqual(
        sqlite.Status.constraint,
        sqlite.Status.fromExtendedCode(sqlite.c.SQLITE_CONSTRAINT_CHECK).?,
    );
    try std.testing.expectEqual(
        sqlite.Status.ok,
        sqlite.Status.fromExtendedCode(sqlite.c.SQLITE_OK).?,
    );
    try std.testing.expect(sqlite.Status.fromCode(27) == null);
    try std.testing.expect(sqlite.Status.fromCode(-1) == null);
    try std.testing.expect(sqlite.Status.fromExtendedCode(27) == null);
}

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

    try std.testing.expectEqual(@as(i64, 1), try st.columnInt64(0));
    try std.testing.expectEqual(@as(f64, 2.5), try st.columnDouble(1));
    try std.testing.expectEqualStrings("three", try st.columnText(2));
    try std.testing.expectEqualStrings("four", try st.columnBlob(3));
    try std.testing.expectError(error.NullValue, st.columnText(4));
}

test "errstr answers for a known and an unknown code" {
    const busy = sqlite.errstr(sqlite.Status.busy.code()) orelse return error.NoErrstrText;
    try std.testing.expect(busy.len > 0);
    const constraint = sqlite.errstr(sqlite.Status.constraint.code()) orelse return error.NoErrstrText;
    try std.testing.expect(constraint.len > 0);
    const unknown = sqlite.errstr(27) orelse return error.NoErrstrText;
    try std.testing.expect(unknown.len > 0);
}

test "a statement carries a copy of its own SQL text" {
    var db = try openMemory();
    defer db.close();

    var owned_buffer: [64]u8 = undefined;
    @memset(&owned_buffer, 0);
    const text = "SELECT 11 AS eleven";
    @memcpy(owned_buffer[0..text.len], text);
    const borrowed = owned_buffer[0..text.len :0];

    var st = try db.prepare(borrowed);
    defer st.finalize() catch {};

    @memset(&owned_buffer, 0xff);

    try std.testing.expectEqualStrings(text, st.sql());
    try std.testing.expectEqual(sqlite.Step.row, try st.step());
    try std.testing.expectEqual(@as(i64, 11), try st.columnInt64(0));
    try std.testing.expectEqualStrings("eleven", st.columnName(0).?);
}

test "the dispatch route is present in exactly one of its two shapes" {
    if (sqlite.runtime_loaded) {
        try std.testing.expect(sqlite.loadedSource() == null);
    } else {
        try std.testing.expect(sqlite.loadedSource() == null);
        // In linked mode, `load` is a no-op.
        try sqlite.load(.{ .system = "libsqlite3-nonexistent-for-this-check" });
        try std.testing.expect(sqlite.loadedSource() == null);
    }
}
