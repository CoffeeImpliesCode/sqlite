// SPDX-License-Identifier: LicenseRef-PublicDomain
// See FORK-LICENSE.md for what that identifier covers.
//! Builds SQLite's runtime-loading module from the selected translate-C output.
//! This route uses generated dispatch instead of linking the native archive.

const std = @import("std");

/// Prefix shared by the synchronization symbols in `runtime/sync.c` and this descriptor.
const sync_prefix = "sqlite_rt";

/// Empty: `sqlite3.h:35` includes only `<stdarg.h>`, which declares no functions.
const libc_noise = "";

/// These header declarations require opt-in features absent from the default amalgamation.
const provider_optional =
    "sqlite3_column_database_name,sqlite3_column_database_name16," ++
    "sqlite3_column_table_name,sqlite3_column_table_name16," ++
    "sqlite3_column_origin_name,sqlite3_column_origin_name16," ++
    "sqlite3_rtree_geometry_callback,sqlite3_rtree_query_callback," ++
    "sqlite3_carray_bind,sqlite3_carray_bind_v2," ++
    "sqlite3_unlock_notify," ++
    "sqlite3_stmt_scanstatus,sqlite3_stmt_scanstatus_v2,sqlite3_stmt_scanstatus_reset," ++
    "sqlite3_snapshot_get,sqlite3_snapshot_open,sqlite3_snapshot_free," ++
    "sqlite3_snapshot_cmp,sqlite3_snapshot_recover," ++
    "sqlite3_mutex_held,sqlite3_mutex_notheld";

/// `sqlite3.h` declares these on every target; SQLite implements them only on Windows.
const provider_windows_only =
    "sqlite3_win32_set_directory,sqlite3_win32_set_directory8,sqlite3_win32_set_directory16";

/// Empty; extension-only `sqlite3_api` is absent from the translated `sqlite3.h` interface.
const provider_excluded = "";

/// Creates a loader core for linked builds to expose `LoadSource` and `LoadError`.
/// Runtime-loaded builds obtain the shared core through the generated dispatch.
pub fn createCoreModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("runtime/loader.zig"),
        .target = target,
        .optimize = optimize,
        // The Unix loader calls libc's `dlopen`.
        .link_libc = true,
    });
}

/// Generates the runtime dispatch from this target's actual translate-C output.
/// This route does not link the C archive.
pub fn createModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
) *std.Build.Module {
    const core = createCoreModule(b, target, optimize);

    const library = b.createModule(.{
        .root_source_file = b.path("runtime/library.zig"),
        .target = target,
        .optimize = optimize,
    });
    library.addImport("rt", core);

    return createDispatchModule(b, translate, target, optimize, core, library);
}

const GeneratedSources = struct {
    native: std.Build.LazyPath,
    dispatch: std.Build.LazyPath,
};

fn createDispatchModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    core: *std.Build.Module,
    library: *std.Build.Module,
) *std.Build.Module {
    const sources = generateDispatch(b, translate, target);

    const dispatch = b.createModule(.{
        .root_source_file = sources.dispatch,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dispatch.addImport("rt", core);
    dispatch.addImport("library", library);
    // Re-export from the patched translation to preserve nominal C types.
    // Its `__root` import routes nested macro references through the dispatch.
    const native = b.createModule(.{
        .root_source_file = sources.native,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    native.addImport("c_routed", dispatch);
    dispatch.addImport("c_native", native);
    dispatch.include_dirs.appendSlice(b.allocator, translate.include_dirs.items) catch @panic("OOM");
    dispatch.addCSourceFiles(.{
        .files = &.{ "runtime/sync.c", "runtime/bind.c" },
        .flags = &.{b.fmt("-DRT_SYNC_PREFIX={s}", .{sync_prefix})},
        .language = .c,
    });
    return dispatch;
}

fn generateDispatch(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
) GeneratedSources {
    const generator = b.addExecutable(.{
        .name = b.fmt("sqlite-runtime-generate-{s}", .{
            target.result.zigTriple(b.allocator) catch @panic("unspellable target"),
        }),
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/generate.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });

    const run = b.addRunArtifact(generator);
    run.addArg("--library");
    run.addArg("sqlite");
    run.addArg("--translate");
    run.addFileArg2(translate.getOutput(), .{});
    if (libc_noise.len != 0) {
        run.addArg("--noise");
        run.addArg(libc_noise);
    }
    if (provider_optional.len != 0) {
        run.addArg("--optional");
        run.addArg(provider_optional);
    }
    if (target.result.os.tag != .windows) {
        run.addArg("--optional");
        run.addArg(provider_windows_only);
    }
    if (provider_excluded.len != 0) {
        run.addArg("--exclude");
        run.addArg(provider_excluded);
    }
    run.addArg("--native-output");
    const native_source = run.addOutputFileArg2("native.zig", .{});
    run.addArg("--output");
    const dispatch_source = run.addOutputFileArg2("dispatch.zig", .{});
    return .{ .native = native_source, .dispatch = dispatch_source };
}
