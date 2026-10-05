// SPDX-License-Identifier: LicenseRef-PublicDomain
// See FORK-LICENSE.md for what that identifier covers.

//! The deterministic example program.
//!
//! `zig build smoke` runs this, and `zig build` compiles it. It is an example,
//! not a test: `tests.zig` holds the behavioural proofs and this file holds none,
//! so nothing here pins a value to prove that a function exists. What it does
//! hold is a working end-to-end path through the published surface — open, bind,
//! step, read, close — over the same twelve-row ledger the tests use, so a
//! reader can see the API used the way a consumer uses it.
//!
//! Three things are printed rather than asserted, and the difference is
//! deliberate:
//!
//!   * the version the *provider* reports, read through the facade at run time.
//!     Under `-Druntime=true` that string comes out of a shared object named on
//!     the command line, so printing it is how a caller sees which SQLite it got;
//!   * `sqlite3_compileoption_used` for a handful of `SQLITE_ENABLE_*` options.
//!     This build defines none of them, so each answer is expected to be zero,
//!     and saying so out loud is more honest than leaving a reader to guess what
//!     "no compile options are defined" means in practice;
//!   * the thread-safety level the library reports for itself.
//!
//! The one value the program checks is arithmetic it did not obtain from SQLite:
//! the ledger is seeded with literal amounts and the grouped sum is compared
//! with the sum written out in the source. A facade that dropped a row or
//! retyped an integer fails here, and it fails on a number computed on paper.

const std = @import("std");
const sqlite = @import("sqlite3");

/// The twelve rows, and the grouped answer, hand-written.
///
/// `a` is 100 + 50 + 300 + 25 - 50 = 425 over five rows; `b` is
/// 250 + 25 - 100 + 400 = 575 over four; `c` is -700 + 75 + 50 = -575 over
/// three. The whole table is 425 over twelve rows. These are the same twelve
/// rows and the same three numbers `tools/fixture/aggregate.sql` seeds and
/// `tools/fixture/expected.tsv` records, so the shell gate and this program
/// answer one question.
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

/// Open a private in-memory database, or say why it did not open.
///
/// `:memory:` is upstream's own special name for a temporary in-memory database
/// that vanishes when the connection closes (`src/sqlite3.h:3833-3835`), so this
/// program writes no file and needs no temporary directory.
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

    // Printed, never compared: a version string is provenance, not behaviour,
    // and the library's own answer to `sqlite3_libversion` is the authority.
    try w.print("sqlite3 smoke\n", .{});
    try w.print("  provider:       {s}\n", .{sqlite.libraryVersion()});
    try w.print("  version number: {d}\n", .{sqlite.libraryVersionNumber()});
    try w.print("  source id:      {s}\n", .{sqlite.sourceId()});
    try w.print("  thread safe:    {d}\n", .{sqlite.threadSafe()});

    // No compile option is defined on any compile line in this build, so each of
    // these asks SQLite itself whether it was configured in. The answers are
    // printed, not asserted: a build that later defines one would change them,
    // and an example that failed on the change would be testing a build policy
    // rather than the API.
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

    // The ledger, through the same binding path a consumer would use: one
    // prepared statement, bound three times, stepped to completion, reused for
    // the next row after a reset.
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

    // The grouped reduction, read back one row at a time. `column_count` is
    // printed rather than checked: it is what the example is demonstrating, and
    // `tests.zig` is where a wrong column count would be a failure.
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

    // The one checked value, against arithmetic written out above rather than
    // obtained from SQLite. Three group sums have to add up to the whole-table
    // sum, which is what catches a row that was counted in one group and missed
    // in another.
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

    // An error the library diagnoses is shown as its own code, because "it
    // failed" is not something a reader can act on.
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