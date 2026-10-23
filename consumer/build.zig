// SPDX-License-Identifier: LicenseRef-PublicDomain
// See ../FORK-LICENSE.md for what that identifier covers.
//! Builds a separate consumer through the published `sqlite3` dependency.
//! Parent builds forward target, linkage and provider options to this graph.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Declare options so direct and nested runs exercise the selected delivery.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Which delivery of libsqlite3 to check. Forwarded to the dependency; it " ++
            "decides the artifact, never anything in this package.",
    ) orelse .static;
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Check the dependency's runtime-loading dispatch instead of a linked " ++
            "one. Forwarded to the dependency. A program built this way has to " ++
            "name a provider with an explicit load() before any native call, " ++
            "which is src/main.zig's business and not this file's.",
    ) orelse false;

    const dep = b.dependency("sqlite3", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime_loaded,
    });

    // The build runner resolves `-fsys` in the shared graph, not through `-D` options.
    // Direct and nested builds use the same choice (`lib/std/Build.zig:2731`).

    // The dependency module owns its libc requirement; do not mask a missing declaration here.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("sqlite3", dep.module("sqlite3"));

    const exe = b.addExecutable(.{
        .name = "sqlite3-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.has_side_effects = true;
    // Forward program arguments so runtime-provider options reach `main.zig`.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
