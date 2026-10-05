// SPDX-License-Identifier: LicenseRef-PublicDomain
// See FORK-LICENSE.md for what that identifier covers.
//
//! SQLite's side of the runtime loader: the names its synchronization binding
//! has, what it requires of a provider beyond resolving its symbols, and what
//! the external ABI boundary for this provider actually is.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them
//! SQLite's, and it is the file another SDK replaces.
//!
//! ## What a provider must be
//!
//! All 366 declarations of `zig/translate.h`, which is exactly `<sqlite3.h>`:
//! the 365 functions and the exported data object `sqlite3_version`
//! (`src/sqlite3.h:188`). All 365 are defined in the amalgamation this package
//! compiles, so `provider_optional` and `provider_excluded` in
//! `runtime/graph.zig` are both empty and a provider that does not export the
//! whole set is refused rather than half used.
//!
//! ## The ABI boundary, stated honestly
//!
//! The supported external ABI family is **SQLite 3** - the `SQLITE_VERSION`
//! major component, `SQLITE_VERSION_NUMBER / 1000000` - built from this header
//! with no compile option defined. That is a narrower claim than "a shared
//! object that exports these names", and the difference is real:
//!
//!   * **The 64-bit integer type is the header's own.** `sqlite3_int64` is
//!     `long long int` on the ordinary path (`src/sqlite3.h:304-307`), so
//!     `sqlite3_column_int64` returns 64 bits and
//!     `SQLITE_MAX_VARIABLE_NUMBER` is 32766 (`src/sqlite3.c:14880`) rather than
//!     999. A provider compiled with `SQLITE_OMIT_FLOATING_POINT` substitutes
//!     the integer type for `double` in the header itself
//!     (`src/sqlite3.h:314-316`) and is a different ABI under the same names.
//!     The runtime check below exercises this rather than assuming it.
//!   * **What the library exports is a choice, not a constant.**
//!     `sqlite3_stricmp` (`src/sqlite3.h:9890`), `sqlite3_strnicmp`
//!     (`:9891`) and `sqlite3_load_extension` are all declared by the header and
//!     defined by the amalgamation; `sqlite3_next_stmt` (`:7109`) and
//!     `sqlite3_txn_state` (`:7060`) are declared and defined but sit behind
//!     `SQLITE_ENABLE_*` guards upstream may turn off. A provider compiled with
//!     `SQLITE_OMIT_LOAD_EXTENSION`, or any other `OMIT`, still exports the
//!     names this header declares and may not export the ones it does not, and
//!     the router's answer to a missing one is `MissingSymbol`. That is why the
//!     provider list here is complete and the optional list is empty: this build
//!     defines no `SQLITE_*` option, so it demands exactly the default build's
//!     symbol set.
//!   * **The allocator is the provider's.** `sqlite3_malloc64`
//!     (`src/sqlite3.h:3319`) and `sqlite3_free` (`:3322`) hand out and take
//!     back memory from whatever allocator the provider was built with, and
//!     nothing in this SDK can observe, bound or account for it: a Zig allocator
//!     is not in the path, and a test framework cannot supply a leak oracle for
//!     memory a third-party allocator owns. The check below creates and drops a
//!     connection, which is the largest single thing that allocator does, and
//!     calls that the whole of what this module can say about it.
//!   * **`sqlite3_config` and friends are variadic.** `sqlite3_config(int, ...)`
//!     (`src/sqlite3.h:1729`), `sqlite3_db_config(sqlite3*, int, ...)`
//!     (`:1748`), `sqlite3_bind_text` (`:5016`) through
//!     `sqlite3_bind_blob` (`:5009`) and the whole `sqlite3_vfs` and
//!     `sqlite3_module` families are function-pointer and varargs shapes that
//!     cross the boundary. A provider whose calling convention for those differs
//!     would pass this table's checks and still be a different ABI; nothing here
//!     claims more than what the checks below actually exercise.
//!
//! **A different major version is refused.** A provider whose
//! `sqlite3_libversion_number` is not in the 3 family is not this library: the
//! 366 names mean something else there. The check is on the *family*, not on
//! the exact number, because upstream's own version contract
//! (`src/sqlite3.h:130-136`) says `SQLITE_VERSION_NUMBER` is always larger than
//! the release it derives from, with `Z` bumped or `Y` incremented - which is
//! exactly the property that makes the major component the stable part and a
//! point release an addition rather than a change.
//!
//! What is checked at load time, before anything is published:
//!
//!   * `sqlite3_libversion_number` answers in the 3 family. That is the ABI
//!     *family* check.
//!   * A `:memory:` database opens, a statement prepares, one step returns
//!     `SQLITE_ROW`, and a column read back is the integer 1. This is done
//!     through the provider's own code and its own allocator, so it exercises
//!     the memory allocator, the VFS's in-memory path, the tokenizer and the
//!     b-tree, and it checks the one scalar width a version number alone does
//!     not: `sqlite3_column_int64` returned an `i64` that round-tripped.
//!   * `sqlite3_libversion` names the same release `sqlite3_libversion_number`
//!     describes, and `sqlite3_sourceid` is the Fossil check-in string
//!     `src/sqlite3.h:151` records. These are read out of the provider, not
//!     compared against this build's constant: a 3.40 provider must be usable,
//!     and the point is to let the caller see which one it got.
//!   * `sqlite3_initialize` and `sqlite3_shutdown` are not called here. They are
//!     process-global (`src/sqlite3.h:1689-1690`) and the loader does not own
//!     the provider's global state; `sqlite3_open_v2` calls
//!     `sqlite3_initialize` itself unless `SQLITE_OMIT_AUTOINIT` is defined
//!     (`src/sqlite3.c:16571` is the WASI arm of that, and this build defines
//!     nothing), so the initialization the check needs has happened by then.
//!
//! Everything above is done through the dispatch table, so the provider under
//! examination is the one the caller asked for and not a second copy of the
//! library this tree happened to link.
const std = @import("std");

const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.c` compiled with
/// `RT_SYNC_PREFIX=sqlite_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn sqlite_rt_lock() void;
    extern fn sqlite_rt_unlock() void;
    extern fn sqlite_rt_wait() void;
    extern fn sqlite_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
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

/// `SQLITE_VERSION_NUMBER / 1000000`, from `src/sqlite3.h:149-150`.
///
/// `SQLITE_VERSION_NUMBER` is `3.53.4` written as `3 * 1000000 + 53 * 1000 + 4`,
/// so the major component is the whole number divided by a million. The header
/// states the formula at `src/sqlite3.h:130-132`.
const version_major: c_int = 3;

/// The value the check puts through the provider and reads back: `SELECT 1`.
///
/// Chosen because it is the smallest statement whose answer crosses the whole
/// library and is an integer, so a 32-bit `sqlite3_int64` could not hide behind
/// it.
const probe_value: i64 = 1;

/// Whether a provider answered a `const char *` entry point with NULL.
///
/// `src/sqlite3.h:189-190` types `sqlite3_libversion` and `sqlite3_sourceid` as
/// `const char *` the provider may answer with NULL, and the generated dispatch
/// carries them as `[*:0]const u8` rather than as an optional, so the null is an
/// address here: `@intFromPtr` is what compares one without inventing an
/// optional the dispatch did not produce.
fn nullPointer(pointer: anytype) bool {
    return @intFromPtr(pointer) == 0;
}

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "sqlite";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated headers, not from this file.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
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

        /// The library-specific checks, run after every symbol resolved and
        /// before anything is published.
        ///
        /// A non-null answer is `ValidationFailed` and the candidate is closed
        /// without being published. Every check here is one whose failure this
        /// code can observe; see the module comment for what is deliberately
        /// not called and why.
        pub fn validate(dst: *const table) ?[]const u8 {
            // The family check. `sqlite3_libversion_number` is a plain function
            // of no arguments that ignores nothing (`src/sqlite3.h:191`), so it
            // is safe to ask before any connection exists, and it is the
            // cheapest way to learn which major version the provider is.
            const family = @divTrunc(dst.sqlite3_libversion_number(), 1_000_000);
            if (family != version_major) {
                // The numbers go to the diagnostic stream rather than into the
                // returned text: `validate` has no allocator and the loader
                // reports whatever string it is given.
                std.debug.print(
                    "sqlite: provider reports sqlite3_libversion_number {d}, this " ++
                        "SDK's headers describe major version {d}; they are " ++
                        "different external ABIs\n",
                    .{ family, version_major },
                );
                return "this provider implements a different major version of " ++
                    "SQLite than the one this SDK's headers describe";
            }

            // The two provider-supplied strings, read once and checked for shape
            // rather than compared against this build. `sqlite3_libversion` and
            // `sqlite3_sourceid` both return storage the provider owns
            // (`src/sqlite3.h:189-190`); neither is compared against
            // `src/sqlite3.h:149-151`, because a 3.40 provider is a legitimate
            // one to load. What is checked is that they are the non-empty,
            // NUL-terminated C strings the header declares - a provider that
            // answered with something else is not describing itself.
            const libversion = dst.sqlite3_libversion();
            if (nullPointer(libversion) or libversion[0] == 0) return
                "sqlite3_libversion returned no version string, so this provider " ++
                    "is not describing itself as a SQLite library";
            const sourceid = dst.sqlite3_sourceid();
            if (nullPointer(sourceid) or sourceid[0] == 0) return
                "sqlite3_sourceid returned no check-in string, so this provider " ++
                    "is not describing itself as a SQLite library";

            // Open one private in-memory database through the provider. `:memory:`
            // is the filename `src/sqlite3.h:3833-3835` names for exactly this,
            // and it reaches no file, so the check leaves nothing behind on a
            // filesystem that is not this process's business.
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
            // `close_v2` never fails and always releases the connection
            // eventually (`src/sqlite3.h:335-343`), so this defer cannot leave
            // a connection behind if a check below returns.
            defer _ = dst.sqlite3_close_v2(handle.?);

            var statement: ?*dispatch.sqlite3_stmt = null;
            const prepared = dst.sqlite3_prepare_v2(
                handle,
                "SELECT 1",
                -1,
                &statement,
                null,
            );
            // `*ppStmt` is set to NULL on error *and* for input that compiles to
            // no statement (`src/sqlite3.h:4539-4542`); a non-zero return is
            // what tells the two apart here, and "SELECT 1" is not the second.
            if (prepared != dispatch.SQLITE_OK or statement == null) return
                "sqlite3_prepare_v2 could not compile the probe statement in this " ++
                    "provider, so its tokenizer, parser and code generator are " ++
                    "not usable";

            // `sqlite3_column_int64` returns the value; there is no status out
            // parameter to read (`src/sqlite3.h:5583`). It is reached only after
            // a row, because that is the only time its answer means anything.
            const stepped = dst.sqlite3_step(statement);
            const value = if (stepped == dispatch.SQLITE_ROW)
                dst.sqlite3_column_int64(statement, 0)
            else
                0;
            const finalized = dst.sqlite3_finalize(statement.?);
            if (stepped != dispatch.SQLITE_ROW) return
                "sqlite3_step did not return SQLITE_ROW for a one-row SELECT in " ++
                    "this provider, so it cannot execute the probe statement";
            if (value != probe_value) return
                "sqlite3_column_int64 did not return the integer the probe " ++
                    "selected, so this provider is not executing the SQL its " ++
                    "header describes";
            // `sqlite3_finalize` reports the most recent evaluation's code
            // (`src/sqlite3.h:5595-5600`), so a non-OK answer here would mean
            // the row it handed out came from a failed evaluation.
            if (finalized != dispatch.SQLITE_OK) return
                "sqlite3_finalize reported an error for a statement that " ++
                    "returned a row, which is a failure this provider cannot " ++
                    "explain from the codes it returned";

            return null;
        }
    };
}
