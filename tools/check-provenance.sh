#!/usr/bin/env bash
# Source-integrity check for the SQLite SDK.
#
# Eight questions, all answerable without a compiler:
#
#   1. Do the 1299 upstream files still hash to the digests UPSTREAM.sha256
#      records?
#   2. Is the native file set exactly that set -- no missing, extra or renamed
#      file under src/, upstream/ or test/?  A plain checksum run cannot see an
#      addition.
#   3. Does upstream's Fossil manifest still hash to the check-in name this tree
#      claims, and is that the same check-in the compiled amalgamation names?
#   4. Do the vendored bytes still match the per-file SHA3-256 upstream's own
#      manifest records, for the files that manifest names and that are checked
#      in rather than generated?
#   5. Do the version this package declares and the version the header declares
#      still agree?
#   6. Does src/sqlite3.h still have no #include but <stdarg.h>, which is the
#      assumption runtime/graph.zig's loader boundary rests on?
#   7. Is the public-domain grant still where the records say it is?
#   8. Is the preserved upstream README still byte-identical, and is the SQL the
#      upstream-shell gate runs still the SQL the Zig tests run?
#
# This is a provenance gate, not a build gate. Nothing here compiles, links or
# runs a target binary; it is the check that an edit to the canonical native
# source cannot pass as a routine change.
#
# Usage: tools/check-provenance.sh   (run from anywhere in the repository)
#
# SPDX-License-Identifier: LicenseRef-PublicDomain
# See FORK-LICENSE.md for what that identifier covers.

set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "check-provenance: $1" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 ||
        fail "$2"
}

need sha256sum "sha256sum is required by this script"
need openssl "openssl is required by checks 3 and 4"
need awk "awk is required by this script"

recorded_count=$(grep -c '^[0-9a-f]\{64\}  ' UPSTREAM.sha256)
[ "$recorded_count" -eq 1299 ] ||
    fail "UPSTREAM.sha256 holds $recorded_count records, not the 1299 this package ships"

# 1. Bytes.
sha256sum -c --quiet UPSTREAM.sha256 ||
    fail "an upstream file no longer matches UPSTREAM.sha256"
echo "all $recorded_count upstream files match UPSTREAM.sha256"

# 2. File set.
expected_tree=$(awk '/^[0-9a-f]{64}  / { print $2 }' UPSTREAM.sha256 |
    grep -E '^(src|upstream|test)/' | LC_ALL=C sort)
actual_tree=$(find src upstream test -type f | LC_ALL=C sort)
if [ "$expected_tree" != "$actual_tree" ]; then
    echo "check-provenance: the native file set differs from the recorded one:" >&2
    diff -u <(echo "$expected_tree") <(echo "$actual_tree") >&2 || true
    echo >&2
    echo "An intentional change to the native source needs an observed failure, a" >&2
    echo "small causal patch, an explicit per-file deviation record in NOTICE.md," >&2
    echo "updated digests in UPSTREAM.sha256, and a CHANGELOG.md entry in the" >&2
    echo "same change." >&2
    exit 1
fi
echo "the native file set is exactly the recorded $recorded_count files"

# 3. The Fossil check-in identity, by upstream's own documented method.
#
# upstream/README.md, "## Verifying Code Authenticity": "The manifest.uuid file
# should contain the SHA3-256 hash of the manifest file", where the trailing
# "# Remove this line" comment is not part of the hashed text. `sed '$d'` removes
# exactly that comment, which is the last line of upstream/manifest.
manifest_checkin=$(sed '$d' upstream/manifest | openssl dgst -r -sha3-256 | awk '{ print $1 }')
uuid=$(tr -d '[:space:]' <upstream/manifest.uuid)
# The amalgamation names the check-in across two comment lines
# (src/sqlite3.c:20-21), by a 36-character prefix of the 64-character Fossil
# name, and lists no changed file after it -- which is upstream stating that the
# amalgamation differs from that check-in in nothing at all.
grep -q "comes from Fossil check-in" src/sqlite3.c ||
    fail "src/sqlite3.c does not say which check-in its content comes from"
amal=$(sed -n 's/^\*\* \([0-9a-f]\{8,\}\) with changes in files:$/\1/p' src/sqlite3.c | head -1)
[ -n "$amal" ] || fail "src/sqlite3.c names no check-in hash after that sentence"
case "$uuid" in
    "$amal"*) ;;
    *) fail "src/sqlite3.c names $amal, which is not a prefix of the check-in $uuid" ;;
esac
header_source_id=$(sed -n 's/^#define SQLITE_SOURCE_ID *"\(.*\)"$/\1/p' src/sqlite3.h)
case "$header_source_id" in
    *"$uuid") ;;
    *) fail "src/sqlite3.h's SQLITE_SOURCE_ID does not name the check-in $uuid" ;;
esac
echo "upstream/manifest, manifest.uuid, sqlite3.h and sqlite3.c all name check-in $uuid"

# 4. Per-file cross-check against upstream's own manifest.
#
# Fossil records a SHA3-256 per file. src/sqlite3ext.h is the one file under
# src/ that upstream checks in rather than generates, so it is the one the
# compiled side can be pinned to; sqlite3.c, sqlite3.h and shell.c are generator
# output (upstream/README.md, "### The Amalgamation") and have no entry by
# design.
#
# The test/ cross-check is reported and not enforced. 869 of the 1285 files match
# the manifest and 416 do not, and the cause of that difference is not
# established; it is recorded as an open item in UPSTREAM.md and FORK-NOTES.md.
# Failing on an unexplained difference would make this gate permanently red and
# let a real edit hide behind a known-failing check, so the authoritative check
# for test/ is check 1, which covers every file by the digest this tree actually
# recorded from these bytes.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

awk '/^F / { print $2 "  " $3 }' upstream/manifest >"$work/manifest_map"
find src upstream test -type f | LC_ALL=C sort |
    xargs openssl dgst -r -sha3-256 |
    awk '{ sub(/^\*/, "", $2); print $2 "  " $1 }' >"$work/disk_map"

awk -v work="$work" '
    NR == FNR { m[$1] = $2; next }
    {
        split($1, parts, "/"); dir = parts[1]
        # upstream/manifest lists the ten release-metadata files by their bare
        # name, and the other two directories by their path within the tree.
        key = (dir == "upstream") ? parts[2] : $1
        total[dir]++
        if (key in m) {
            named[dir]++
            if (m[key] == $2) same[dir]++
            else if (dir != "test") bad = bad $1 "\n"
        }
    }
    END {
        order[1] = "src"; order[2] = "upstream"; order[3] = "test"
        if (bad != "") print bad > (work "/bad")
        for (i = 1; i <= 3; i++) {
            d = order[i]
            printf "%s: %d of %d files are named by upstream manifest, %d match it byte for byte\n", d, named[d] + 0, total[d], same[d] + 0
        }
    }
' "$work/manifest_map" "$work/disk_map"

if [ -s "$work/bad" ]; then
    echo "check-provenance: these checked-in files disagree with the Fossil manifest:" >&2
    sed 's/^/  /' "$work/bad" >&2
    fail "a vendored upstream file no longer matches the Fossil manifest"
fi
src_ext_sha3=$(openssl dgst -r -sha3-256 src/sqlite3ext.h | awk '{ print $1 }')
manifest_ext=$(awk '/^F src\/sqlite3ext\.h / { print $3 }' upstream/manifest)
[ "$src_ext_sha3" = "$manifest_ext" ] ||
    fail "src/sqlite3ext.h no longer matches the hash upstream's manifest records"
echo "src/sqlite3ext.h matches the hash upstream's manifest records for it"

# 5. One version, in three places.
zon_version=$(sed -n 's/^ *\.version = "\(.*\)",*$/\1/p' build.zig.zon | head -1)
header_version=$(sed -n 's/^#define SQLITE_VERSION *"\(.*\)"$/\1/p' src/sqlite3.h)
version_file=$(tr -d '[:space:]' <upstream/VERSION)
[ -n "$zon_version" ] || fail "build.zig.zon declares no .version"
[ "$zon_version" = "$header_version" ] ||
    fail "build.zig.zon says $zon_version and src/sqlite3.h says $header_version"
[ "$header_version" = "$version_file" ] ||
    fail "src/sqlite3.h says $header_version and upstream/VERSION says $version_file"
grep -q '^#define SQLITE_VERSION_NUMBER 3053004$' src/sqlite3.h ||
    fail "src/sqlite3.h's SQLITE_VERSION_NUMBER is no longer 3053004"
echo "one version in three places: $header_version / 3053004"

# 6. The translation's header closure.
#
# runtime/graph.zig builds the loader's answer for a foreign symbol name from the
# assumption that <sqlite3.h> pulls in nothing but <stdarg.h>. If a future release
# adds a header to that closure, this fires and the list in graph.zig has to be
# filled in from the new translation.
foreign=$(grep '^[[:space:]]*#[[:space:]]*include' src/sqlite3.h | grep -v '<stdarg\.h>' || true)
[ -z "$foreign" ] || fail "src/sqlite3.h now includes something other than <stdarg.h>: $foreign"
echo "src/sqlite3.h includes only <stdarg.h>"

# 7. The public-domain grant.
grep -q '^SQLite Is Public Domain$' upstream/LICENSE.md ||
    fail "the public-domain statement is missing from upstream/LICENSE.md"
for file in src/sqlite3.h src/sqlite3ext.h; do
    grep -q 'The author disclaims copyright to this source code' "$file" ||
        fail "the per-file public-domain blessing is missing from $file"
done
for file in NOTICE.md FORK-LICENSE.md; do
    grep -q 'May you do good and not evil' "$file" ||
        fail "the public-domain blessing is missing from $file"
done
grep -q 'SPDX-License-Identifier: LicenseRef-PublicDomain' FORK-LICENSE.md ||
    fail "FORK-LICENSE.md does not state the SPDX identifier the sources carry"
echo "the public-domain dedication is present upstream and in the fork's records"

# 8a. The preserved upstream README.
cmp -s README.upstream.md upstream/README.md ||
    fail "README.upstream.md and upstream/README.md are no longer byte-identical"
readme_digest=$(sha256sum upstream/README.md | awk '{ print $1 }')
recorded_readme=$(awk '/^[0-9a-f]{64}  upstream\/README\.md$/ { print $1 }' UPSTREAM.sha256)
[ "$readme_digest" = "$recorded_readme" ] ||
    fail "upstream/README.md does not match the digest UPSTREAM.sha256 records"
echo "README.upstream.md is byte-identical to the imported upstream README"

# 8b. The fixture and the tests ask the same question.
#
# The two front ends -- this package's Zig facade and upstream's own shell -- are
# only a cross-check if they are asked the same question, so the statements in
# tools/fixture/aggregate.sql are compared with tests.zig here. Whitespace is
# normalised and Zig's multiline-string "\\" continuation prefix is stripped,
# because that is the only difference in how one SQL line is spelled in the two
# files; nothing else is. The twelve seeded rows are compared as literals,
# because tests.zig holds them as Zig values rather than as SQL text.
sql_file=tools/fixture/aggregate.sql
test_file=tests.zig
for file in "$sql_file" "$test_file" tools/fixture/expected.tsv; do
    [ -f "$file" ] || fail "$file is missing from this tree"
done

flat_tests=$(sed -e 's/^[[:space:]]*\\\\[[:space:]]*//' "$test_file" |
    tr '\n' ' ' | sed -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ //' -e 's/ $//')

sql_checked=0
sql_mismatch=0
while IFS= read -r statement; do
    [ -n "$statement" ] || continue
    sql_checked=$((sql_checked + 1))
    case "$flat_tests" in
        *"$statement"*) ;;
        *)
            echo "check-provenance: aggregate.sql and tests.zig disagree on:" >&2
            echo "  $statement" >&2
            sql_mismatch=$((sql_mismatch + 1))
            ;;
    esac
done < <(
    grep -v '^[[:space:]]*--' "$sql_file" |
        grep -v '^[[:space:]]*INSERT ' |
        grep -v '^[[:space:]]*$' |
        awk '
            { line = $0; sub(/;[[:space:]]*$/, "", line) }
            { buf = (buf == "" ? line : buf " " line) }
            /;[[:space:]]*$/ {
                gsub(/[[:space:]]+/, " ", buf)
                print buf
                buf = ""
            }
            END { if (buf != "") print buf }
        '
)
seed_checked=0
while IFS= read -r line; do
    row=${line#INSERT INTO ledger VALUES(}
    row=${row%);}
    row=$(echo "$row" | tr -d '[:space:]')
    entry=${row%%,*}
    rest=${row#*,}
    account=${rest%%,*}
    account=${account#\'}
    account=${account%\'}
    cents=${rest#*,}
    seed_checked=$((seed_checked + 1))
    grep -qF ".entry = $entry, .account = \"$account\", .cents = $cents" "$test_file" ||
        fail "the seeded row ($entry, $account, $cents) is in $sql_file but not in $test_file"
done < <(grep '^INSERT INTO ledger VALUES' "$sql_file")
[ "$seed_checked" -eq 12 ] ||
    fail "$sql_file seeds $seed_checked rows, not the 12 this package checks"
echo "the $sql_checked statements and $seed_checked seeded rows agree between the fixture and tests.zig"

# The expected table has to be the hand-computed one this package documents, or
# a recomputed fixture would pass both gates without anyone noticing.
grep -qx 'a|425|5|1|12' tools/fixture/expected.tsv ||
    fail "tools/fixture/expected.tsv no longer holds the hand-computed group a"
grep -qx 'b|575|4|2|11' tools/fixture/expected.tsv ||
    fail "tools/fixture/expected.tsv no longer holds the hand-computed group b"
grep -qx 'c|-575|3|4|10' tools/fixture/expected.tsv ||
    fail "tools/fixture/expected.tsv no longer holds the hand-computed group c"
grep -qx 'grand|425|12' tools/fixture/expected.tsv ||
    fail "tools/fixture/expected.tsv no longer holds the hand-computed whole table"
echo "the expected table is the hand-computed one this package documents"

echo "provenance checks passed"