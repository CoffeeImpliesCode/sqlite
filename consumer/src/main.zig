// SPDX-License-Identifier: LicenseRef-PublicDomain
// See ../FORK-LICENSE.md for what that identifier covers.

//! Consumes the `sqlite3` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `dep.module` in
//! `build.zig`, and `@import("sqlite3")` here. No path reaches into the
//! library's own tree, so if this builds and produces the answers below, the
//! module contract is real: the typed facade, the translated headers it
//! re-exports as `c`, and the native library behind both arrived through one
//! dependency line.
//!
//! ## What the answers are
//!
//! The one check is a **hand-computed aggregation**, and the arithmetic is done
//! on paper rather than obtained from SQLite. The table below is seeded with
//! twelve literal rows, the same twelve `tools/fixture/aggregate.sql` seeds,
//! and the answer is spelled out in the source:
//!
//! ```text
//!   a: 100 + 50 + 300 + 25 - 50 =  425   5 rows   entries 1, 3, 6, 9, 12
//!   b: 250 + 25 - 100 + 400     =  575   4 rows   entries 2, 5, 8, 11
//!   c: -700 + 75 + 50           = -575   3 rows   entries 4, 7, 10
//!
//!   whole table                   425  over 12 rows
//! ```
//!
//! A facade that dropped a row, decoded an integer as a narrower type,
//! reordered a column or answered `done` one step early disagrees with that
//! arithmetic, and the program exits non-zero. It is not the same code run
//! twice: the numbers below were computed from the rows, not read back out of
//! the library and compared with itself.
//!
//! The other two printed lines are printed rather than compared. The provider's
//! own version string and source id are provenance, and under `-Druntime=true`
//! they come out of a shared object named on the command line — showing the
//! caller which SQLite it got is the point of printing them.
//!
//! ## The same source builds against a linked package and a runtime-loaded one
//!
//! `sqlite.runtime_loaded` is a comptime constant, so the difference is one
//! branch and no duplicated program: in the runtime-loaded build the provider is
//! named on the command line (`--provider <path>`) or in `SQLITE_TEST_PROVIDER`,
//! loaded once, and the same answers follow.

const std = @import("std");
const sqlite = @import("sqlite3");

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// The twelve seeded rows, as Zig values, and the grouped answer by hand.
///
/// Written out rather than generated: a fixture whose expected value came from
/// the same code that produced the observed value would prove nothing. The sums
/// are spelled out in the module comment above and repeated as literals below so
/// that a reader can check them against the rows without running anything.
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
    sum: i64,
    count: i64,
    first: i64,
    last: i64,
};

/// The answer, computed from the rows above on paper.
///
/// `a`: 100 + 50 + 300 + 25 - 50 = 425, five rows, entries 1 through 12.
/// `b`: 250 + 25 - 100 + 400 = 575, four rows, entries 2 through 11.
/// `c`: -700 + 75 + 50 = -575, three rows, entries 4 through 10.
/// Whole table: 425 + 575 - 575 = 425 over twelve rows.
const expected = [_]Bucket{
    .{ .name = "a", .sum = 425, .count = 5, .first = 1, .last = 12 },
    .{ .name = "b", .sum = 575, .count = 4, .first = 2, .last = 11 },
    .{ .name = "c", .sum = -575, .count = 3, .first = 4, .last = 10 },
};

/// The provider this run should load, from `--provider <path>` or from
/// `SQLITE_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location, and a build
/// that was not told which file to load says so rather than loading something
/// else.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get("SQLITE_TEST_PROVIDER") orelse
        return noProvider();
}

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export SQLITE_TEST_PROVIDER with a shared object exporting the 366 " ++
            "declarations of zig/translate.h, which is exactly <sqlite3.h>. " ++
            "Nothing is loaded by default and no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

/// Open a private in-memory database, or say why it did not open.
fn openMemory() !sqlite.Db {
    const opened = try sqlite.Db.open(":memory:", .{ .readwrite = true, .create = true });
    return switch (opened) {
        .ok => |db| db,
        .failed => |failure| {
            std.debug.print("consumer: open failed, code {d}: {s}\n", .{
                failure.code,
                failure.message(),
            });
            return error.OpenFailed;
        },
        .no_connection => |code| {
            std.debug.print("consumer: no connection at all, code {d}\n", .{code});
            return error.NoConnection;
        },
    };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [8192]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // In a runtime-loading build every call below goes through a table that this
    // one call fills. In a linked build the branch is not analyzed at all.
    if (comptime sqlite.runtime_loaded) {
        try sqlite.load(.{ .path = try providerRequest(init) });
    }

    try w.print("sqlite3 consumer\n", .{});
    // Through the library's own accessors, so these lines name the provider this
    // build reached rather than constants compiled into this program. They are
    // printed, not compared: a version string is provenance, not behaviour.
    try w.print("{s: <34}{s}\n", .{
        if (sqlite.runtime_loaded) "loaded" else "linked",
        sqlite.libraryVersion(),
    });
    try w.print("{s: <34}{s}\n", .{ "provider source id", sqlite.sourceId() });

    var db = try openMemory();
    defer db.close();

    try db.exec(
        \\CREATE TABLE ledger(entry INTEGER NOT NULL, account TEXT NOT NULL, cents INTEGER NOT NULL)
    );

    // One prepared statement, bound three times, reused for every row. A
    // dependent that prepared per row would work too; this shape is what the
    // facade's reset/finalize ownership is written for.
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

    var grouped = try db.prepare(
        \\SELECT account, SUM(cents), COUNT(*), MIN(entry), MAX(entry)
        \\  FROM ledger
        \\ GROUP BY account
        \\ ORDER BY account
    );
    defer grouped.finalize() catch {};

    var seen: usize = 0;
    var total: i64 = 0;
    while (true) {
        switch (try grouped.step()) {
            .done => break,
            .row => {
                if (seen >= expected.len) return error.TooManyRows;
                const want = expected[seen];
                const name = try grouped.columnText(0);
                const sum = try grouped.columnInt64(1);
                const count = try grouped.columnInt64(2);
                const first = try grouped.columnInt64(3);
                const last = try grouped.columnInt64(4);
                total += sum;

                try w.print("{s: <34}{s} {d} {d} {d} {d}\n", .{
                    "account row", name, sum, count, first, last,
                });
                try checkString("grouped account", name, want.name);
                try checkInt("grouped sum", sum, want.sum);
                try checkInt("grouped row count", count, want.count);
                try checkInt("grouped first entry", first, want.first);
                try checkInt("grouped last entry", last, want.last);
                seen += 1;
            },
        }
    }
    try checkInt("account groups read", @as(i64, @intCast(seen)), @as(i64, 3));

    // The whole-table reduction, which is what catches a GROUP BY that lost or
    // duplicated a row rather than one that mis-typed a column: the three group
    // sums have to add up to it, and the three group counts to its count.
    var whole = try db.prepare(
        \\SELECT SUM(cents), COUNT(*) FROM ledger
    );
    defer whole.finalize() catch {};

    _ = try whole.step();
    const whole_sum = try whole.columnInt64(0);
    const whole_rows = try whole.columnInt64(1);
    try checkInt("whole-table sum", whole_sum, 425);
    try checkInt("whole-table rows", whole_rows, 12);
    try checkInt("group sums add up to it", total, whole_sum);

    // A failure the library diagnoses is a code a caller can act on, not a
    // message to guess from.
    if (db.exec("SELECT * FROM a_table_that_does_not_exist")) |_| {
        std.debug.print("consumer: a query against a missing table succeeded\n", .{});
        return error.ConsumerCheckFailed;
    } else |err| {
        try w.print("{s: <34}{s} (code {d})\n", .{
            "a missing table is reported as",
            @errorName(err),
            db.errcode(),
        });
    }

    try w.print("every answer matched the hand-computed table\n", .{});
    try w.flush();
}

/// A checked integer. The expected value is the one written out in the module
/// comment, not a value this program obtained from the library.
fn checkInt(what: []const u8, got: i64, want: i64) !void {
    if (got != want) {
        std.debug.print("consumer: {s}: expected {d}, computed {d}\n", .{
            what,
            want,
            got,
        });
        return error.ConsumerCheckFailed;
    }
}

/// A checked string, with the same rule: the expected value is a literal.
fn checkString(what: []const u8, got: []const u8, want: []const u8) !void {
    if (!std.mem.eql(u8, got, want)) {
        std.debug.print("consumer: {s}: expected \"{s}\", computed \"{s}\"\n", .{
            what,
            want,
            got,
        });
        return error.ConsumerCheckFailed;
    }
}