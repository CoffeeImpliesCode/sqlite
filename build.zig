// SPDX-License-Identifier: LicenseRef-PublicDomain
// See FORK-LICENSE.md for what that identifier covers.
//
//! Builds SQLite's bundled library and shell, or links an installed library.
//! Linkage controls delivery; runtime controls facade dispatch.
const std = @import("std");

/// Runtime and linked facades share loader-core types.
/// Only the runtime facade adds dispatch.
const graph = @import("runtime/graph.zig");

const manifest = @import("build.zig.zon");

/// Parsed manifest version; invalid values fail at configuration.
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

/// Package, module and C artifact share upstream's name, `sqlite3`.
/// Consumers use `dep.module("sqlite3")` or `-lsqlite3`.
const lib_name = "sqlite3";

const facade_source = "zig/root.zig";

/// Header routed for translation; see `zig/translate.h` for its wrapper role.
const translate_header = "zig/translate.h";

const test_source = "tests.zig";

const example_source = "smoke.zig";

const source_dir = "src";

/// Upstream release version; the build checks it against the manifest.
const upstream_version: std.SemanticVersion = .{ .major = 3, .minor = 53, .patch = 4 };

/// Shared ABI major matches upstream's `libsqlite3.so.0` soname.
const abi_version: std.SemanticVersion = .{ .major = 0, .minor = 53, .patch = 4 };

const core_sources = [_][]const u8{
    "src/sqlite3.c",
};

/// Upstream's amalgamated shell, built as the `sqlite3` executable.
const Program = struct {
    name: []const u8,
    source: []const u8,
};

const shell: Program = .{ .name = "sqlite3", .source = "src/shell.c" };

/// Installed headers; `sqlite3ext.h` is not translated.
const public_headers = [_][]const u8{
    "src/sqlite3.h",
    "src/sqlite3ext.h",
};

/// Licence and provenance records installed under `share/licenses/sqlite/`.
const licence_records = [_][]const u8{
    "upstream/LICENSE.md",
    "src/sqlite3.h",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "UPSTREAM.sha256",
    "FORK-NOTES.md",
    "CHANGELOG.md",
};

/// GNU C11 enables the language features used by the amalgamation.
const c_flags = [_][]const u8{"-std=gnu11"};

const Library = enum {
    bundled,
    system,
};

const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// Matrix artifact names include the target triple.
fn programName(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    base: []const u8,
    public: bool,
) []const u8 {
    if (public) return base;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}-{s}", .{ base, lib_name, triple });
}

/// Per-target C link and program settings.
const Platform = struct {
    /// No platform-specific `SQLITE_*` macros are defined.
    macros: []const [2][]const u8,
    /// Whether math functions need a separate library.
    separate_m: bool,
    /// Whether `dlopen` needs a separate library.
    separate_dl: bool,
    /// Whether pthread needs a separate library.
    /// Windows target marker; `SQLITE_API` needs no export list by default.
    separate_pthread: bool,
    dll: bool,
    /// Program-only WASI emulation flags; the library needs none.
    /// Keep these separate from platform macros and link requirements.
    wasi_emulation: []const [2][]const u8,

    fn forTarget(target: std.Build.ResolvedTarget) Platform {
        const os_tag = target.result.os.tag;
        if (os_tag == .windows) {
            // Windows supplies math and loading; SQLite uses Win32 mutexes.
            return .{
                .macros = &.{},
                .separate_m = false,
                .separate_dl = false,
                .separate_pthread = false,
                .dll = true,
                .wasi_emulation = &.{},
            };
        }
        if (os_tag == .wasi) {
            // Upstream disables extensions and threading on WASI; wasi-libc supplies math.
            // Shell-only compatibility flags are defined below.
            return .{
                .macros = &.{},
                .separate_m = false,
                .separate_dl = false,
                .separate_pthread = false,
                .dll = false,
                .wasi_emulation = &.{
                    .{ "_WASI_EMULATED_SIGNAL", "wasi-emulated-signal" },
                    .{ "_WASI_EMULATED_PROCESS_CLOCKS", "wasi-emulated-process-clocks" },
                    .{ "_WASI_EMULATED_GETPID", "wasi-emulated-getpid" },
                },
            };
        }
        if (os_tag.isDarwin()) {
            // Darwin provides `dlopen` and pthread through its C runtime.
            return .{
                .macros = &.{},
                .separate_m = true,
                .separate_dl = false,
                .separate_pthread = false,
                .dll = false,
                .wasi_emulation = &.{},
            };
        }
        // Other Unix targets need separate math, loader and pthread libraries.
        return .{
            .macros = &.{},
            .separate_m = true,
            .separate_dl = true,
            .separate_pthread = true,
            .dll = false,
            .wasi_emulation = &.{},
        };
    }

    fn kind(platform: Platform) []const u8 {
        if (platform.macros.len != 0) return "a platform macro this build defines";
        if (platform.separate_m and platform.separate_dl and platform.separate_pthread)
            return "upstream's own detection: -lm -ldl -lpthread";
        if (platform.separate_m)
            return "upstream's own detection: -lm";
        return "upstream's own detection: no separate link library";
    }
};

/// Library and facade modules for one target.
const Graph = struct {
    /// Null when system mode links the installed library.
    c_lib: ?*std.Build.Step.Compile,
    /// Facade bound to this graph's declarations.
    module: *std.Build.Module,
    /// Resolved platform requirements for this target.
    platform: Platform,
};

fn artifactName(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    public: bool,
) []const u8 {
    if (public) return lib_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}", .{ lib_name, triple });
}

/// Builds one target's library and facade.
/// Matrix checks use private modules to avoid duplicate registered names.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    library: Library,
    linkage: std.lang.LinkMode,
    runtime_loaded: bool,
    public: bool,
) Graph {
    const platform = Platform.forTarget(target);

    const c_lib: ?*std.Build.Step.Compile = if (library == .bundled)
        add_c_library(b, target, optimize, linkage, platform, artifactName(b, target, public))
    else
        null;

    // Resolve translation settings from the same target as the C library.
    const no_macros: []const [2][]const u8 = &.{};
    const translate_macros = if (library == .bundled) platform.macros else no_macros;
    const translate_include: ?std.Build.LazyPath =
        if (library == .bundled) b.path(source_dir) else null;

    const translate = b.addTranslateC(.{
        .root_source_file = b.path(translate_header),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    if (translate_include) |dir| {
        // Bundled mode translates the bundled header; system mode uses the default include path.
        translate.addIncludePath(dir);
    }
    // Keep translation macros aligned with the C compilation.
    for (translate_macros) |macro| translate.defineCMacro(macro[0], macro[1]);

    // System mode requires installed headers on the compiler's default include path.
    // The `.pc` file supplies linkage, not a translation include path.
    if (library == .system) {
        translate.linkSystemLibrary(lib_name, .{ .preferred_link_mode = linkage });
    }

    const module = if (public)
        b.addModule(lib_name, .{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
    // Runtime dispatch and linked facades share declarations from one translation.
    // Linkage controls delivery; runtime controls facade dispatch, not the shell.
    if (runtime_loaded) {
        // Runtime dispatch does not link the provider; the library is still built for delivery.
        module.addImport("c", graph.createModule(b, translate, target, optimize));
    } else {
        // Import translated declarations through the facade, not as a public module.
        module.addImport("c", translate.createModule());
        module.addImport("rt", graph.createCoreModule(b, target, optimize));
        // System linkage is attached by TranslateC above.
        if (c_lib) |lib| module.linkLibrary(lib);
    }

    // Expose bundled headers to dependent C consumers.
    // System mode does not add the bundled source include path.
    if (library == .bundled) module.addIncludePath(b.path(source_dir));

    return .{ .c_lib = c_lib, .module = module, .platform = platform };
}

/// Compiles the SQLite amalgamation for one target.
/// Dynamic delivery adds the ABI version and PIC; C sources stay unchanged.
fn add_c_library(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    requested: std.lang.LinkMode,
    platform: Platform,
    name: []const u8,
) *std.Build.Step.Compile {
    const linkage = deliveredLinkage(target, requested);
    const c_lib = b.addLibrary(.{
        .name = name,
        .linkage = linkage,
        // Dynamic libraries use upstream's ABI soname; static archives have no version.
        .version = if (linkage == .dynamic) abi_version else null,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            // SQLite and the shell use the target C runtime.
            .link_libc = true,
            // Shared objects require position-independent code.
            .pic = if (linkage == .dynamic) true else null,
            // Keep Debug/safe UB checks without requiring Zig's UBSan runtime
            // when a plain C compiler links the installed archive.
            .sanitize_c = if (optimize == .debug or optimize == .safe) .trap else .off,
        }),
    });
    const c_mod = c_lib.root_module;

    // Local quoted headers in the amalgamation and shell need this include path.
    c_mod.addIncludePath(b.path(source_dir));

    // Match the compile-time macros to the target's platform configuration.
    for (platform.macros) |macro| {
        c_mod.addCMacro(macro[0], macro[1]);
    }

    for (core_sources) |source| {
        c_mod.addCSourceFile(.{
            .file = b.path(source),
            .flags = &c_flags,
        });
    }

    // Add only the system libraries required by this target.
    if (platform.separate_m) c_mod.linkSystemLibrary("m", .{});
    if (platform.separate_dl) c_mod.linkSystemLibrary("dl", .{});
    if (platform.separate_pthread) c_mod.linkSystemLibrary("pthread", .{});

    // Install upstream's public headers with the library.
    for (public_headers) |header| {
        c_lib.installHeader(b.path(header), std.fs.path.basename(header));
    }

    return c_lib;
}

/// Builds upstream's `sqlite3` shell with the selected linkage.
/// It uses the same target-specific libraries and WASI compatibility flags.
fn add_program(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    linkage: std.lang.LinkMode,
    platform: Platform,
    c_lib: *std.Build.Step.Compile,
    program: Program,
    name: []const u8,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // The executable itself need not be position independent.
    });
    mod.addIncludePath(b.path(source_dir));
    for (platform.macros) |macro| mod.addCMacro(macro[0], macro[1]);

    mod.addCSourceFile(.{
        .file = b.path(program.source),
        .flags = &c_flags,
    });
    if (platform.separate_m) mod.linkSystemLibrary("m", .{});
    if (platform.separate_dl) mod.linkSystemLibrary("dl", .{});
    if (platform.separate_pthread) mod.linkSystemLibrary("pthread", .{});
    // Each WASI compatibility macro is paired with its wasi-libc provider.
    for (platform.wasi_emulation) |emulation| {
        mod.addCMacro(emulation[0], "1");
        mod.linkSystemLibrary(emulation[1], .{});
    }
    mod.linkLibrary(c_lib);
    // The installed executable and shared library are siblings.
    // Use a prefix-relative path, not a LazyPath resolved in the build cache.
    if (linkage == .dynamic) {
        if (installedRPath(target)) |rpath| mod.addRPathSpecial(rpath);
    }

    return b.addExecutable(.{ .name = name, .root_module = mod });
}

/// Relative loader path from `bin/sqlite3` to `lib/libsqlite3.so.0`.
/// Null for formats without RPATH support.
fn installedRPath(target: std.Build.ResolvedTarget) ?[]const u8 {
    return switch (target.result.ofmt) {
        .elf => "$ORIGIN/../lib",
        .macho => "@loader_path/../lib",
        else => null,
    };
}

/// Builds the library, facade, tests, example and shell for one target.
fn add_target_check(
    b: *std.Build,
    step: *std.Build.Step,
    cross_target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    library: Library,
    linkage: std.lang.LinkMode,
    runtime_loaded: bool,
) void {
    // Matrix artifact names include the target triple.
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("unspellable target");

    const cross = addGraph(b, cross_target, optimize, library, linkage, runtime_loaded, false);

    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addTest(.{
        .name = b.fmt("sqlite3-tests-{s}", .{triple}),
        .root_module = test_mod,
    }).step);

    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addExecutable(.{
        .name = b.fmt("sqlite3-smoke-{s}", .{triple}),
        .root_module = example_mod,
    }).step);

    // System mode has no local library or shell to link.
    if (cross.c_lib) |c_lib| {
        step.dependOn(&add_program(
            b,
            cross_target,
            optimize,
            linkage,
            cross.platform,
            c_lib,
            shell,
            programName(b, cross_target, shell.name, false),
        ).step);
    }
}

/// Runs the separate consumer against this build's resolved configuration.
/// The nested build inherits this graph's target, CPU, optimization and linkage.
/// Cross targets install; Zig 0.17 exposes no runner flags during configuration.
fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    library: Library,
    linkage: std.lang.LinkMode,
    runtime_loaded: bool,
) *std.Build.Step.Run {
    const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    // CPU model and features are separate from the target triple.
    // Build arguments copy these strings before the temporary allocations are freed.
    const cpu = target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // Reuse the compiler running this build script, not PATH.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    // Keep relative environment paths anchored at the parent's working directory.
    run.addArg("--build-file");
    run.addFileArg2(b.path("consumer/build.zig"), .{ .make_absolute = true });
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    // Forward CPU features so the consumer matches the library's target.
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    // Forward delivery and dispatch so the nested build checks the same graph.
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));
    // Forward explicit true/false so the nested build preserves this setting.
    run.addArg(b.fmt("-Druntime={s}", .{if (runtime_loaded) "true" else "false"}));
    // Forward the resolved system-integration flag; it is not a `-D` option.
    // This keeps the nested dependency in the same mode as this graph.
    run.addArg(if (library == .system) b.fmt("-fsys={s}", .{lib_name}) else b.fmt("-fno-sys={s}", .{lib_name}));
    // Keep nested build parallelism and summaries aligned with this workspace.
    run.addArg("-j8");
    run.addArg("--summary");
    run.addArg("all");
    run.addArg("--cache-dir");
    run.addDirectoryArg2(
        .{ .relative = .{ .base = .local_cache, .sub_path = "consumer" } },
        .{ .make_absolute = true },
    );
    // Inherit the maker's current environment; a configurer-time clone becomes stale.
    // This includes SQLITE_TEST_PROVIDER, ZIG_GLOBAL_CACHE_DIR and ZIG_LIB_DIR.
    // Use the parent's install prefix for any nested installation.
    // DESTDIR is inherited through the environment.
    run.addArg("--prefix");
    run.addDirectoryArg2(
        .{ .relative = .{ .base = .install_prefix } },
        .{ .make_absolute = true },
    );
    // Pass caller args after `--`, separate from the nested build options.
    // This forwards consumer arguments such as `--provider`.
    run.addArg("--");
    run.addPassthruArgs();
    run.has_side_effects = true;
    return run;
}

/// Returns whether this build can execute the target natively.
/// Zig 0.17 does not expose third-party runner flags while configuring.
fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = b.graph.host.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .host_cpu_arch = host.cpu.arch,
        .host_os_tag = host.os.tag,
        .link_mode = .dynamic,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(b.graph.io, &target.result, options)) {
        .native => true,
        else => false,
    };
}

/// Writes upstream-compatible `sqlite3.pc` metadata and installs it.
/// Its `prefix` is relative to `pcfiledir`, so it works under any install prefix.
/// `Libs.private` lists target-specific libraries for static consumers.
fn add_pkg_config(b: *std.Build, platform: Platform, linkage: std.lang.LinkMode) void {
    const files = b.addWriteFiles();
    // Depend on the install-file step so `sqlite3.pc` ships with `zig build`.
    const install_pc = b.addInstallFileWithDir(
        files.add("sqlite3.pc", b.fmt(
            \\# sqlite3.pc for the SQLite {f} SDK.
            \\#
            \\# Generated from upstream/sqlite3.pc.in, which is upstream's own template:
            \\# Name and Description are its lines 11-12, Libs its line 14, and
            \\# Libs.private its line 15 with the two entries this configuration does
            \\# not need removed - @LDFLAGS_ZLIB@, because sqlite3.c reaches zlib only
            \\# behind SQLITE_ENABLE_FTS5 which this build does not define, and
            \\# @LDFLAGS_ICU@, likewise. `prefix` is pcfiledir-relative so the
            \\# installed file is correct wherever --prefix put it.
            \\prefix=${{pcfiledir}}/../..
            \\exec_prefix=${{prefix}}
            \\libdir=${{prefix}}/lib
            \\includedir=${{prefix}}/include
            \\
            \\Name: SQLite
            \\Description: SQL database engine
            \\Version: {f}
            \\
            \\Requires:
            \\Libs: -L"${{libdir}}" -lsqlite3
            \\Libs.private:{s}{s}{s}
            \\Cflags: -I"${{includedir}}"
            \\
        , .{
            upstream_version,
            upstream_version,
            if (platform.separate_m) " -lm" else "",
            if (platform.separate_dl) " -ldl" else "",
            if (platform.separate_pthread) " -lpthread" else "",
        })),
        .prefix,
        "lib/pkgconfig/sqlite3.pc",
    );
    b.getInstallStep().dependOn(&install_pc.step);
    _ = linkage;
}

/// Installs licence and provenance records under `share/licenses/sqlite/`.
fn install_licence_records(b: *std.Build) void {
    for (licence_records) |record| {
        const install_record = b.addInstallFileWithDir(
            b.path(record),
            .prefix,
            b.fmt("share/licenses/sqlite/{s}", .{std.fs.path.basename(record)}),
        );
        b.getInstallStep().dependOn(&install_record.step);
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const system_default = b.option(
        bool,
        "system",
        "Link an installed libsqlite3 instead of compiling src/, and translate the " ++
            "installed headers instead of the bundled ones. This supplies the " ++
            "default of systemIntegrationOption(\"sqlite3\"); a build runner that " ++
            "decides the mode itself (-fsys=sqlite3) overrides it. Not gated in " ++
            "this wave: see build.zig's module comment on system mode.",
    ) orelse false;

    const use_system = b.systemIntegrationOption(lib_name, .{ .default = system_default });
    const library: Library = if (use_system) .system else .bundled;

    const linkage_option = b.option(
        std.lang.LinkMode,
        "linkage",
        "Deliver the native library as a static archive (the default) or as a real " ++
            "shared object with upstream's libsqlite3.so.0 ABI name. This selects " ++
            "the delivery and never the dispatch: the same amalgamated translation " ++
            "unit is compiled either way. In system mode this graph builds no " ++
            "artifact at all, so there the option names the kind of installed " ++
            "library to bind to instead, and it defaults to dynamic.",
    );

    // Bundled mode defaults to static; system mode follows Zig's dynamic default.
    // Preserve each mode's default independently.
    const linkage: std.lang.LinkMode = linkage_option orelse
        (if (library == .system) .dynamic else .static);

    // Runtime dispatch is independent of linkage and does not change delivery.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve the native entry points at run time instead of linking them. " ++
            "The facade keeps the same translated headers and the same public " ++
            "types; each selected native function becomes a dispatch through " ++
            "one process-lifetime table that an explicit load(source) fills, " ++
            "and the module links no archive. Independent of -Dlinkage, which " ++
            "still decides which artifact this build delivers and installs. " ++
            "Default off, and a linked build is unchanged in every respect.",
    ) orelse false;

    // The manifest version must match the upstream amalgamation.
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the version read out " ++
            "of src/sqlite3.h; see UPSTREAM.md");
    }

    const published = addGraph(b, target, optimize, library, linkage, runtime_loaded, true);

    if (published.c_lib) |c_lib| {
        b.installArtifact(c_lib);
        add_pkg_config(b, published.platform, deliveredLinkage(target, linkage));
        install_licence_records(b);

        const shell_exe = add_program(
            b,
            target,
            optimize,
            linkage,
            published.platform,
            c_lib,
            shell,
            programName(b, target, shell.name, true),
        );
        b.installArtifact(shell_exe);
        addOracle(b);
    }

    // Compile the example as a facade/linkage check; do not install it.
    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, published.module);
    const example = b.addExecutable(.{
        .name = "sqlite3-smoke",
        .root_module = example_mod,
    });
    b.getInstallStep().dependOn(&example.step);

    // The smoke run builds the executable without depending on installation.
    const run_example = b.addRunArtifact(example);
    run_example.has_side_effects = true;
    run_example.addPassthruArgs();
    b.step("smoke", "Run the deterministic example program").dependOn(&run_example.step);

    // Root the test step in `tests.zig` so Zig discovers its test blocks.
    // Cross-target execution is left to the selected runner.
    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, published.module);
    const unit_tests = b.addTest(.{
        .name = "sqlite3-tests",
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.has_side_effects = true;
    const test_step = b.step("test", "Run the behavioural tests and bundled-provider consumer");
    test_step.dependOn(&run_tests.step);
    if (targetHasDynamicLinker(target)) {
        const runtime_graph = addGraph(b, target, optimize, .bundled, .dynamic, true, false);
        const consumer_mod = b.createModule(.{
            .root_source_file = b.path("consumer/src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        consumer_mod.addImport(lib_name, runtime_graph.module);
        const runtime_consumer = b.addExecutable(.{
            .name = "sqlite3-default-provider-consumer",
            .root_module = consumer_mod,
        });
        const run_runtime_consumer = b.addRunArtifact(runtime_consumer);
        run_runtime_consumer.addArg("--provider");
        run_runtime_consumer.addFileArg2(runtime_graph.c_lib.?.getEmittedBin(), .{ .make_absolute = true });
        run_runtime_consumer.addArg("--expect-default-features");
        run_runtime_consumer.has_side_effects = true;
        // This consumer links musl statically, whose dlopen always returns NULL.
        const can_run_runtime_consumer = !target.result.isMuslLibC();
        if (can_run_runtime_consumer) {
            test_step.dependOn(&run_runtime_consumer.step);
        } else {
            test_step.dependOn(&runtime_consumer.step);
            test_step.dependOn(&runtime_graph.c_lib.?.step);
        }
        if (can_run_runtime_consumer and b.graph.host.result.os.tag == .linux and target.result.os.tag == .linux and hostCanExecute(b, target)) {
            const prime_consumer = b.addSystemCommand(&.{ "env", "-u", "SQLITE_TEST_PROVIDER" });
            prime_consumer.setName("configure consumer without provider");
            const env_consumer = b.addSystemCommand(&.{"env"});
            env_consumer.setName("consumer package with environment-only provider");
            env_consumer.addFileArg2(runtime_graph.c_lib.?.getEmittedBin(), .{
                .prefix = "SQLITE_TEST_PROVIDER=",
                .make_absolute = true,
            });
            for ([_]*std.Build.Step.Run{ prime_consumer, env_consumer }) |run| {
                run.addArgs(&.{ b.graph.zig_exe, "build", "--build-file" });
                run.addFileArg2(b.path("build.zig"), .{ .make_absolute = true });
                run.addArgs(&.{ "consumer", "-Druntime=true", "-fno-sys=sqlite3" });
                run.addArg(b.fmt("-Dtarget={s}", .{
                    target.query.zigTriple(b.allocator) catch @panic("OOM"),
                }));
                run.addArg(b.fmt("-Dcpu={s}", .{
                    target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM"),
                }));
                run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
                run.addArg("--cache-dir");
                run.addDirectoryArg2(
                    .{ .relative = .{ .base = .local_cache, .sub_path = "consumer-env" } },
                    .{ .make_absolute = true },
                );
                run.addArg("-j8");
            }
            prime_consumer.addArg("--print-configuration-path");
            prime_consumer.has_side_effects = true;
            env_consumer.step.dependOn(&prime_consumer.step);
            env_consumer.addArgs(&.{ "--", "--expect-default-features" });
            env_consumer.has_side_effects = true;
            test_step.dependOn(&env_consumer.step);
        }
    }

    // Run the separate consumer with this graph's resolved mode.
    // Cross targets install; Zig 0.17 exposes no third-party runner flags at configuration time.
    b.step("consumer", "Build or run the consumer/ package for the selected target")
        .dependOn(&runConsumer(b, target, optimize, library, deliveredLinkage(target, linkage), runtime_loaded).step);

    // Compile every selected target's library and programs without running them.
    const check_step = b.step(
        "check",
        "Compile the native library, the facade, the tests, the example and " ++
            "the sqlite3 shell for supported check targets without running any of them",
    );
    if (!target.query.isNative()) {
        add_target_check(b, check_step, target, optimize, library, linkage, runtime_loaded);
    } else {
        // The matrix omits targets without loaders when delivery or dispatch needs one.
        for (check_targets[0..]) |query| {
            const cross_target = b.resolveTargetQuery(query);
            if ((linkage == .dynamic or runtime_loaded) and !targetHasDynamicLinker(cross_target)) continue;
            add_target_check(b, check_step, cross_target, optimize, library, linkage, runtime_loaded);
        }
    }

    if (published.c_lib != null) {
        std.debug.print(
            "sqlite: 1 amalgamated translation unit, no SQLITE_* compile option defined, {s}\n",
            .{published.platform.kind()},
        );
        std.debug.print("sqlite: {s}\n", .{switch (deliveredLinkage(target, linkage)) {
            .static => "static archive libsqlite3.a (default)",
            .dynamic => b.fmt("shared object libsqlite3.so.{d}.{d}.{d}, soname libsqlite3.so.{d}", .{
                abi_version.major,
                abi_version.minor,
                abi_version.patch,
                abi_version.major,
            }),
        }});
        if (runtime_loaded) {
            // Report runtime dispatch separately from the delivered artifact.
            std.debug.print(
                "sqlite: runtime-loaded dispatch (-Druntime=true); the facade module " ++
                    "links no archive and a provider is named by an explicit " ++
                    "load(source)\n",
                .{},
            );
        }
    } else {
        std.debug.print("sqlite: system libsqlite3 (-lsqlite3) and the installed headers; this package installs nothing and builds no shell\n", .{});
        if (runtime_loaded) {
            std.debug.print(
                "sqlite: runtime-loaded dispatch (-Druntime=true) over the installed " ++
                    "provider named by an explicit load(source)\n",
                .{},
            );
        }
    }
}

/// Compares the facade's output with upstream's shell on a fixed fixture.
/// Uses the installed shell so dynamic builds find the library beside it.
/// `tools/check-oracle.sh` can also run outside this build graph.
fn addOracle(b: *std.Build) void {
    const oracle = b.step(
        "oracle",
        "Run upstream's sqlite3 shell over tools/fixture/aggregate.sql and " ++
            "compare its output with tools/fixture/expected.tsv",
    );
    const run = b.addSystemCommand(&.{"bash"});
    run.setName("sqlite3 fixture oracle");
    run.step.dependOn(b.getInstallStep());
    run.addFileArg2(b.path("tools/check-oracle.sh"), .{});
    run.addFileArg2(
        .{ .relative = .{ .base = .install_bin, .sub_path = shell.name } },
        .{ .make_absolute = true },
    );
    // The script writes a temporary file; its exit code reports the comparison.
    run.has_side_effects = true;
    oracle.dependOn(&run.step);
}

/// Whether this OS can load shared objects; Windows uses PE/COFF, WASI has none.
fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Rejects unsupported shared delivery; never substitutes a static archive.
/// All build paths use this result to keep artifacts and metadata consistent.
fn deliveredLinkage(
    target: std.Build.ResolvedTarget,
    requested: std.lang.LinkMode,
) std.lang.LinkMode {
    if (requested == .static) return .static;
    if (targetHasDynamicLinker(target)) return .dynamic;

    const os_tag = target.result.os.tag;
    std.process.fatal(
        \\zig build: -Dlinkage=dynamic was asked for {s}, whose operating system has
        \\no dynamic linker, so no shared object can be built or loaded there.
        \\std.Target.DynamicLinker.kind reports `{s}` for it, which is what this
        \\build uses to decide.
        \\
        \\Nothing is substituted: an archive installed under a shared object's name
        \\is a result the caller did not ask for. Use -Dlinkage=static for this
        \\target; the compiled C is identical either way.
        \\
    , .{ @tagName(os_tag), @tagName(std.Target.DynamicLinker.kind(os_tag)) });
}
