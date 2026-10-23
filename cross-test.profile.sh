# cross-test settings profile for SQLite.
# Sourced by cross-test; keep this file to variable assignments only.

# Leave CROSS_MATRIX and TARGETS unset to use the full published matrix.
# Run the standard test step; executor and build-only decisions belong to the harness.

# Four jobs limit memory pressure from SQLite's large translation units.
# Do not filter targets; upstream and build.zig determine platform support.

CROSS_BUILD_STEP=test
CROSS_BUILD_JOBS=4
CROSS_BUILD_TIMEOUT=5400
CROSS_TIMEOUT=1800