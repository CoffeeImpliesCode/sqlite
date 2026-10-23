// SPDX-License-Identifier: LicenseRef-PublicDomain
// See FORK-LICENSE.md for what that identifier covers.

//! End-to-end example of the SQLite facade: seed a ledger, report provider details, and query it.
//! It checks the grouped total against hand-computed values.

const std = @import("std");
const sqlite = @import("sqlite3");

/// Twelve fixture rows; expected sums are a=425 (5 rows), b=575 (4), and c=-575 (3).
const ledger = [_]struct { entry: i64, account: []const u8, cents: i64 }{
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

/// The hand-computed answer this program checks the library against.
const expected_total: i64 = 425;
const expected_rows: i64 = 12;

/// Opens a private in-memory database and reports open failures.
fn openMemory() !sqlite.Db {
    const opened = try sqlite.Db.open(":memory:", .{ .readwrite = true, .create = true });
    return switch (opened) {
        .ok => |db| db,
        .failed => |failure| {
            std.debug.print("sqlite3-smoke: open failed, code {d}: {s}\n", .{
                failure.code,
                failure.message(),
            });
            return error.OpenFailed;
        },
        .no_connection => |code| {
            std.debug.print("sqlite3-smoke: no connection at all, code {d}\n", .{code});
            return error.NoConnection;
        },
    };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var out_buffer: [8192]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &out_buffer);
    const w = &stdout.interface;

    try w.print("sqlite3 smoke\n", .{});
    try w.print("  provider:       {s}\n", .{sqlite.libraryVersion()});
    try w.print("  version number: {d}\n", .{sqlite.libraryVersionNumber()});
    try w.print("  source id:      {s}\n", .{sqlite.sourceId()});
    try w.print("  thread safe:    {d}\n", .{sqlite.threadSafe()});

    // Display compile options instead of pinning build features in this example.
    try w.print("  compiled in:\n", .{});
    for ([_][:0]const u8{
        "SQLITE_ENABLE_FTS5",
        "SQLITE_ENABLE_JSON1",
        "SQLITE_ENABLE_MATH_FUNCTIONS",
        "SQLITE_ENABLE_RTREE",
        "SQLITE_ENABLE_COLUMN_METADATA",
    }) |option| {
        try w.print("    {s: <32}{s}\n", .{
            option,
            if (sqlite.c.sqlite3_compileoption_used(option) != 0) "yes" else "no",
        });
    }

    var db = try openMemory();
    defer db.close();

    try db.exec(
        \\CREATE TABLE ledger(entry INTEGER NOT NULL, account TEXT NOT NULL, cents INTEGER NOT NULL)
    );

    var insert = try db.prepare(
        \\INSERT INTO ledger VALUES(?1, ?2, ?3)
    );
    defer insert.finalize() catch {};
    for (ledger) |row| {
        insert.reset();
        try insert.bindInt64(1, row.entry);
        try insert.bindText(2, row.account);
        try insert.bindInt64(3, row.cents);
        try insert.runToCompletion();
    }

    var grouped = try db.prepare(
        \\SELECT account, SUM(cents), COUNT(*), MIN(entry), MAX(entry)
        \\  FROM ledger
        \\ GROUP BY account
        \\ ORDER BY account
    );
    defer grouped.finalize() catch {};

    try w.print("  grouped by account (SQLite reports {d} columns):\n", .{
        grouped.columnCount(),
    });

    var seen: i64 = 0;
    var total: i64 = 0;
    while (true) {
        switch (try grouped.step()) {
            .done => break,
            .row => {
                seen += 1;
                const sum = try grouped.columnInt64(1);
                const count = try grouped.columnInt64(2);
                total += sum;
                try w.print("    {s: <4} sum {d: <7} rows {d:<4} entries {d}..{d}\n", .{
                    try grouped.columnText(0),
                    sum,
                    count,
                    try grouped.columnInt64(3),
                    try grouped.columnInt64(4),
                });
            },
        }
    }

    if (seen != 3) {
        std.debug.print("sqlite3-smoke: expected 3 account groups, read {d}\n", .{seen});
        return error.SmokeCheckFailed;
    }

    // Compare grouped totals with the hand-computed whole-table answer.
    var whole = try db.prepare(
        \\SELECT SUM(cents), COUNT(*) FROM ledger
    );
    defer whole.finalize() catch {};

    _ = try whole.step();
    const whole_sum = try whole.columnInt64(0);
    const whole_rows = try whole.columnInt64(1);

    if (total != whole_sum or total != expected_total or whole_rows != expected_rows) {
        std.debug.print(
            "sqlite3-smoke: groups total {d} over {d} rows, whole table {d} over {d}; " ++
                "the hand-computed answer is {d} over {d}\n",
            .{ total, seen, whole_sum, whole_rows, expected_total, expected_rows },
        );
        return error.SmokeCheckFailed;
    }

    // Print SQLite's result code with the error for an actionable diagnosis.
    if (db.exec("SELECT * FROM a_table_that_does_not_exist")) |_| {
        std.debug.print("sqlite3-smoke: a query against a missing table succeeded\n", .{});
        return error.SmokeCheckFailed;
    } else |err| {
        try w.print("  a missing table is reported as {s}, code {d}\n", .{
            @errorName(err),
            db.errcode(),
        });
    }

    try w.print("  the twelve seeded rows sum to {d}, which is the hand-computed answer\n", .{
        whole_sum,
    });
    try w.print("sqlite3 smoke completed\n", .{});
    try w.flush();
}
