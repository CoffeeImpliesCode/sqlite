// SPDX-License-Identifier: LicenseRef-PublicDomain
// See ../FORK-LICENSE.md for what that identifier covers.

//! Exercises the public `sqlite3` package in linked and runtime-loaded builds.
//! Expected aggregates are hand-computed; provider version and source ID are reported, not treated as behavior.

const std = @import("std");
const builtin = @import("builtin");
const sqlite = @import("sqlite3");

const ConfigurationError = error{NoProviderConfigured};

/// Twelve literal rows for the independent consumer check.
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

const Bucket = struct {
    name: []const u8,
    sum: i64,
    count: i64,
    first: i64,
    last: i64,
};

/// Hand-computed aggregate expected from `rows`.
const expected = [_]Bucket{
    .{ .name = "a", .sum = 425, .count = 5, .first = 1, .last = 12 },
    .{ .name = "b", .sum = 575, .count = 4, .first = 2, .last = 11 },
    .{ .name = "c", .sum = -575, .count = 3, .first = 4, .last = 10 },
};

/// Reads `--provider` or `SQLITE_TEST_PROVIDER`; missing configuration is an error.
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

/// Reports that a runtime-loaded build needs an explicit provider.
fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export SQLITE_TEST_PROVIDER with a SQLite 3 shared library. " ++
            "Column metadata, RTree, Carray, unlock-notify, scanstatus, snapshot and " ++
            "debug mutex entry points depend on provider features; Win32 directory " ++
            "entry points are optional outside Windows. Other translated symbols are required. " ++
            "Nothing is loaded by default and no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

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

    // Load the provider before any runtime-dispatched call.
    if (comptime sqlite.runtime_loaded) {
        try sqlite.load(.{ .path = try providerRequest(init) });
        const args = try init.minimal.args.toSlice(init.arena.allocator());
        for (args) |arg| {
            if (std.mem.eql(u8, arg, "--expect-default-features")) {
                const optional_count: i64 = 19 +
                    @as(i64, @intFromBool(@hasDecl(sqlite.c, "sqlite3_mutex_held"))) +
                    @as(i64, @intFromBool(@hasDecl(sqlite.c, "sqlite3_mutex_notheld"))) +
                    @as(i64, if (builtin.target.os.tag == .windows) 0 else 3);
                try checkInt("optional feature symbols", @intCast(sqlite.c.optional_symbols.len), optional_count);
                inline for (sqlite.c.optional_symbols, 0..) |symbol, index| {
                    if (sqlite.c.optional(index)) {
                        std.debug.print("consumer: default provider exports feature symbol {s}\n", .{symbol.name});
                        return error.ConsumerCheckFailed;
                    }
                }
                const carray_symbols = [_][]const u8{
                    "sqlite3_carray_bind",
                    "sqlite3_carray_bind_v2",
                };
                for (carray_symbols) |name| {
                    var found = false;
                    for (sqlite.c.optional_symbols) |symbol| {
                        if (std.mem.eql(u8, name, symbol.name)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) return error.ConsumerCheckFailed;
                }
                const win32_symbols = [_][]const u8{
                    "sqlite3_win32_set_directory",
                    "sqlite3_win32_set_directory8",
                    "sqlite3_win32_set_directory16",
                };
                const platform_symbols = if (builtin.target.os.tag == .windows)
                    sqlite.c.symbols
                else
                    sqlite.c.optional_symbols;
                for (win32_symbols) |name| {
                    var found = false;
                    for (platform_symbols) |symbol| {
                        if (std.mem.eql(u8, name, symbol.name)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) return error.ConsumerCheckFailed;
                }
            }
        }
    }

    try w.print("sqlite3 consumer\n", .{});
    try w.print("{s: <34}{s}\n", .{
        if (sqlite.runtime_loaded) "loaded" else "linked",
        sqlite.libraryVersion(),
    });
    try w.print("{s: <34}{s}\n", .{ "provider source id", sqlite.sourceId() });

    var db = try openMemory();
    defer db.close();

    try checkTransientBindings(db);

    try db.exec(
        \\CREATE TABLE ledger(entry INTEGER NOT NULL, account TEXT NOT NULL, cents INTEGER NOT NULL)
    );

    // Reuse one statement to exercise the facade's reset/finalize ownership.
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

    // Compare whole-table totals with group totals to detect omitted or duplicated rows.
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

fn checkTransientBindings(db: sqlite.Db) !void {
    var statement = try db.prepare("SELECT ?1, ?2");
    defer statement.finalize() catch {};

    var text = [_]u8{ 'a', 0, 'b' };
    var blob = [_]u8{ 0, 1, 0xff, 0x7f };
    try statement.bindText(1, &text);
    try statement.bindBlob(2, &blob);
    @memset(&text, 'x');
    @memset(&blob, 0);

    if (try statement.step() != .row) return error.ConsumerCheckFailed;
    try checkString("copied text with embedded NUL", try statement.columnText(0), "a\x00b");
    try checkString("copied blob", try statement.columnBlob(1), "\x00\x01\xff\x7f");

    statement.reset();
    try statement.bindText(1, "");
    try statement.bindBlob(2, "");
    if (try statement.step() != .row) return error.ConsumerCheckFailed;
    if (statement.columnType(0) != .text or statement.columnType(1) != .blob)
        return error.ConsumerCheckFailed;
    try checkString("empty text", try statement.columnText(0), "");
    try checkString("empty blob", try statement.columnBlob(1), "");
}

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
