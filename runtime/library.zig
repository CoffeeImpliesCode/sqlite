// SPDX-License-Identifier: LicenseRef-PublicDomain
// See FORK-LICENSE.md for what that identifier covers.
//! Describes SQLite's provider contract for the runtime loader.
//! Requires translated SQLite 3 symbols except feature- and target-dependent exports.
//! Validates the version family, provider strings and an in-memory `SELECT 1` before publication.
const std = @import("std");

const rt = @import("rt");

/// Binds `runtime/sync.c`'s `sqlite_rt` symbols to the loader synchronization interface.
pub const Sync = struct {
    extern fn sqlite_rt_lock() void;
    extern fn sqlite_rt_unlock() void;
    extern fn sqlite_rt_wait() void;
    extern fn sqlite_rt_broadcast() void;
    // Matches C `unsigned long long` on supported targets.
    extern fn sqlite_rt_thread_self() u64;

    pub fn lock() void {
        sqlite_rt_lock();
    }
    pub fn unlock() void {
        sqlite_rt_unlock();
    }
    pub fn wait() void {
        sqlite_rt_wait();
    }
    pub fn broadcast() void {
        sqlite_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return sqlite_rt_thread_self();
    }
};

/// SQLite major version: `SQLITE_VERSION_NUMBER / 1000000` (`src/sqlite3.h:149-150`).
const version_major: c_int = 3;

/// Expected integer returned by the `SELECT 1` probe.
const probe_value: i64 = 1;

/// Detects NULL from generated non-optional `const char *` declarations.
/// SQLite declares these provider-owned strings at `src/sqlite3.h:189-190`.
fn nullPointer(pointer: anytype) bool {
    return @intFromPtr(pointer) == 0;
}

/// Binds the generated dispatch to SQLite's sync interface and provider validation.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Name shown in pre-load diagnostics.
        pub const library_name = "sqlite";

        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Rejects a provider before publication; non-null text becomes `ValidationFailed`.
        /// Checks SQLite 3, provider strings and an in-memory `SELECT 1`.
        pub fn validate(dst: *const table) ?[]const u8 {
            const family = @divTrunc(dst.sqlite3_libversion_number(), 1_000_000);
            if (family != version_major) {
                // Print version details; validation has no allocator for error text.
                std.debug.print(
                    "sqlite: provider reports sqlite3_libversion_number {d}, this " ++
                        "SDK's headers describe major version {d}; they are " ++
                        "different external ABIs\n",
                    .{ family, version_major },
                );
                return "this provider implements a different major version of " ++
                    "SQLite than the one this SDK's headers describe";
            }

            // Accept any SQLite 3 release and validate provider-owned strings, not exact version equality.
            // The header types both results as `const char *` (`src/sqlite3.h:189-190`).
            const libversion = dst.sqlite3_libversion();
            if (nullPointer(libversion) or libversion[0] == 0) return "sqlite3_libversion returned no version string, so this provider " ++
                "is not describing itself as a SQLite library";
            const sourceid = dst.sqlite3_sourceid();
            if (nullPointer(sourceid) or sourceid[0] == 0) return "sqlite3_sourceid returned no check-in string, so this provider " ++
                "is not describing itself as a SQLite library";

            // Use `:memory:` so the provider check does not touch the filesystem (`src/sqlite3.h:3833-3835`).
            var handle: ?*dispatch.sqlite3 = null;
            const opened = dst.sqlite3_open_v2(
                ":memory:",
                &handle,
                dispatch.SQLITE_OPEN_READWRITE | dispatch.SQLITE_OPEN_MEMORY,
                null,
            );
            if (opened != dispatch.SQLITE_OK or handle == null) {
                if (handle) |leftover| _ = dst.sqlite3_close_v2(leftover);
                return "sqlite3_open_v2 could not open a private in-memory " ++
                    "database in this provider, so its allocator and VFS are " ++
                    "not usable";
            }
            // `close_v2` eventually releases the connection on every return (`src/sqlite3.h:335-343`).
            defer _ = dst.sqlite3_close_v2(handle.?);

            var statement: ?*dispatch.sqlite3_stmt = null;
            const prepared = dst.sqlite3_prepare_v2(
                handle,
                "SELECT 1",
                -1,
                &statement,
                null,
            );
            // A NULL statement also means empty SQL; check the result code (`src/sqlite3.h:4539-4542`).
            if (prepared != dispatch.SQLITE_OK or statement == null) return "sqlite3_prepare_v2 could not compile the probe statement in this " ++
                "provider, so its tokenizer, parser and code generator are " ++
                "not usable";

            // Read only after `SQLITE_ROW`; the API has no status output (`src/sqlite3.h:5583`).
            const stepped = dst.sqlite3_step(statement);
            const value = if (stepped == dispatch.SQLITE_ROW)
                dst.sqlite3_column_int64(statement, 0)
            else
                0;
            const finalized = dst.sqlite3_finalize(statement.?);
            if (stepped != dispatch.SQLITE_ROW) return "sqlite3_step did not return SQLITE_ROW for a one-row SELECT in " ++
                "this provider, so it cannot execute the probe statement";
            if (value != probe_value) return "sqlite3_column_int64 did not return the integer the probe " ++
                "selected, so this provider is not executing the SQL its " ++
                "header describes";
            // `sqlite3_finalize` reports the last evaluation result (`src/sqlite3.h:5595-5600`).
            if (finalized != dispatch.SQLITE_OK) return "sqlite3_finalize reported an error for a statement that " ++
                "returned a row, which is a failure this provider cannot " ++
                "explain from the codes it returned";

            return null;
        }
    };
}
