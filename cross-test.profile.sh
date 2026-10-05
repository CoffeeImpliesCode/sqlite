# cross-test settings profile for the SQLite SDK.
#
# `cross-test` looks for this file at the root of the project it is run from
# (or names it with --profile; --no-profile ignores it). It is trusted Bash that
# the harness `source`s, so this file is *settings only*: ordinary variable
# assignments and nothing else. No command runs, no compiler is probed, and no
# path in here names a host.
#
# There is deliberately no CROSS_MATRIX. The published 53-platform Zig 0.16
# Tier 1/2 table is the matrix this package is checked against, and a matrix
# named here would replace it. There is no TARGETS array either, for the same
# reason: a subset selected here would narrow the run rather than add to it.
# Both belong on the command line, where --targets selects from the active
# matrix and never adds to it.
#
# CROSS_BUILD_STEP stays the standard `test` step, which is what this profile
# states explicitly. There are no `cross_build_command` / `cross_artifact`
# hooks here, so the harness keeps its standard Zig-build mode and runs
# `zig build test -Dtarget=TARGET` per target with a fresh cache. What that
# means for a given target is the harness's decision, not this package's: a
# host target runs, a foreign target runs under whatever executor the harness
# detects (QEMU user mode, Wine, wasmtime), and a foreign target with no
# executor is reported as build-only coverage -- compiled, never executed, and
# never counted as a pass. `build.zig` gives the test binary a Run step for
# every target, which is what leaves that choice open.
#
# The job count is low for a reason specific to this package, and it is worth
# naming rather than leaving to be rediscovered. SQLite's library is *one*
# translation unit, `src/sqlite3.c` at 269 649 lines and 9 515 341 bytes, and
# `src/shell.c` is another at 37 415 lines. A cell therefore compiles two very
# large units rather than a few dozen small ones, and each unit's own peak
# memory use is what limits the job count -- four concurrent cells keep the
# machine's memory the constraint rather than its cores. `zig build` does not
# parallelise within a translation unit, so raising this number buys nothing on
# the step that dominates a cell.
#
# Nothing here narrows the gate to what is expected to work. Which platforms
# SQLite itself supports is decided by upstream's own detection inside
# `src/sqlite3.c` -- the OS arm at `src/sqlite3.c:16538-16548`, the mutex
# selection at `src/sqlite3.c:18417-18425`, and the `__wasi__` arm at
# `src/sqlite3.c:11676-11685` -- and `build.zig` resolves the three link
# libraries each of those implies. A cell that fails is a fact to record and
# diagnose; it is not a reason to drop the cell, sample the tests or remap Debug
# to an optimized mode to make it pass.

CROSS_BUILD_STEP=test
CROSS_BUILD_JOBS=4
CROSS_BUILD_TIMEOUT=5400
CROSS_TIMEOUT=1800