#!/usr/bin/env bash
# Upstream-interop fixture gate: run upstream's own `sqlite3` shell over the
# fixture SQL and compare its output with the hand-computed table.
#
# What this proves, and what it does not
# -------------------------------------
# `tools/fixture/aggregate.sql` is executed by `src/shell.c` - upstream's own C
# client, with its own SQL front end, its own value formatting and its own output
# code - against the library this package compiled. Its stdout is compared byte
# for byte with `tools/fixture/expected.tsv`, the table hand-computed from the
# twelve seeded rows in the SQL file and written before any gate was run.
#
# So the same SQL text is answered by two independent front ends and checked
# against one independently derived answer. A facade that mis-decoded an integer,
# truncated a text value or reordered a column disagrees with the shell here, and
# an expected table that was wrong for both would have to be wrong in the same
# way twice.
#
# What this is *not*: it is not a run of SQLite's own TCL test suite. That suite
# lives in `test/` (vendored whole, unedited) and needs a `testfixture` binary
# built by upstream's makefile plus TCL 8.6; build.zig says so at length and
# never pretends otherwise. This is a small, independent interoperability check,
# not a substitute for that suite.
#
# It runs whatever `sqlite3` binary it is given, so it checks an installed
# prefix as well as this repository's build. It needs a host that can execute
# that binary; on a cross target it is build-only coverage and this script is not
# the gate for it.
#
# Usage:
#   tools/check-oracle.sh                       # zig-out/bin/sqlite3
#   tools/check-oracle.sh /usr/bin/sqlite3      # any installed shell
#
# SPDX-License-Identifier: LicenseRef-PublicDomain

set -euo pipefail

cd "$(dirname "$0")/.."

shell_bin="${1:-zig-out/bin/sqlite3}"
sql="tools/fixture/aggregate.sql"
expected="tools/fixture/expected.tsv"

if [ ! -x "$shell_bin" ]; then
    echo "check-oracle: '$shell_bin' is not an executable; run 'zig build oracle'" >&2
    echo "or pass the path of an installed sqlite3 shell as the first argument." >&2
    exit 1
fi
for file in "$sql" "$expected"; do
    if [ ! -f "$file" ]; then
        echo "check-oracle: $file is missing from this tree" >&2
        exit 1
    fi
done

# Scratch. `mktemp -d` honours TMPDIR, which this workspace's
# `. "$HOME/.local/lib/host-scratch.sh"` points at an approved large mount. The
# directory is removed on every exit, including a failure, and nothing is written
# anywhere else: the database is `:memory:`, so the run touches no file at all.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

actual="$workdir/actual.tsv"

# `-batch` turns off interactive mode, so a read error is a non-zero exit rather
# than a prompt. `-list` and `-separator |` ask for the row-per-line,
# pipe-separated form the fixture is written in, so this is a byte comparison
# against a fixture file and not a parse of something that was formatted first.
# The `.read` argument is how a script file is given to this shell on the command
# line, which keeps the run free of a stdin pipe.
"$shell_bin" -batch -noheader -list -separator '|' :memory: ".read $PWD/$sql" \
    >"$actual"

if ! diff -u "$expected" "$actual"; then
    echo >&2
    echo "check-oracle: upstream's shell did not answer the fixture as" >&2
    echo "expected.tsv says it must. The table on the right is what it printed." >&2
    echo "If the SQL or the fixture changed, recompute the expected table by hand" >&2
    echo "from the rows in $sql and change it in the same commit." >&2
    exit 1
fi

rows="$(wc -l <"$expected" | tr -d ' ')"
echo "check-oracle: $shell_bin answered $sql exactly as $expected ($rows rows)"
echo "check-oracle: upstream interop fixture passed"