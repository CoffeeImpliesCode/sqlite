-- The fixture both proofs read.
--
-- `tools/check-oracle.sh` runs this file through upstream's own `sqlite3` shell
-- (`src/shell.c`) and compares its output with `expected.tsv`, byte for byte.
-- `tests.zig` runs the same twelve rows and the same two queries through this
-- package's Zig facade and checks the same table.
--
-- Two independent front ends, one SQL text, one hand-computed answer. The
-- numbers are all integers on purpose: SQLite prints an integer exactly, so the
-- comparison is a text comparison and a facade that truncated or retyped a value
-- cannot hide behind floating-point formatting.
--
-- The rows are written as literals, never as a generator. There is no
-- `randomblob()`, no `row_number()` and no dependence on a row order: a
-- fixture whose value came from an algorithm is a fixture whose expected answer
-- has to come from the same algorithm.
--
-- `tools/check-provenance.sh` checks that this file and `tests.zig` ask the
-- same question, in the two forms each file spells it in: the three
-- non-INSERT statements below are matched verbatim against `tests.zig` after
-- whitespace is collapsed to single spaces and `tests.zig`'s Zig `\\`
-- line-continuation prefix is stripped, and each of the twelve
-- `INSERT INTO ledger VALUES` rows is matched against the Zig literal
-- `.entry = N, .account = "X", .cents = M` in the `rows` table of
-- `tests.zig`, where the twelve rows are Zig values rather than SQL text.
-- The row count is checked against twelve as well. The two cannot drift apart
-- silently.

CREATE TABLE ledger(entry INTEGER NOT NULL, account TEXT NOT NULL, cents INTEGER NOT NULL);

INSERT INTO ledger VALUES(1,  'a',  100);
INSERT INTO ledger VALUES(2,  'b',  250);
INSERT INTO ledger VALUES(3,  'a',   50);
INSERT INTO ledger VALUES(4,  'c', -700);
INSERT INTO ledger VALUES(5,  'b',   25);
INSERT INTO ledger VALUES(6,  'a',  300);
INSERT INTO ledger VALUES(7,  'c',   75);
INSERT INTO ledger VALUES(8,  'b', -100);
INSERT INTO ledger VALUES(9,  'a',   25);
INSERT INTO ledger VALUES(10, 'c',   50);
INSERT INTO ledger VALUES(11, 'b',  400);
INSERT INTO ledger VALUES(12, 'a',  -50);

-- Grouped reduction, ordered by account so the row order is the answer's, not
-- the planner's. Four columns per account: the name, the exact integer sum, the
-- row count, and the first and last entry numbers in that account.
--
-- Hand-computed from the twelve rows above:
--
--   a: 100 + 50 + 300 + 25 - 50 =  425   5 rows   entries 1, 3, 6, 9, 12
--   b: 250 + 25 - 100 + 400     =  575   4 rows   entries 2, 5, 8, 11
--   c: -700 + 75 + 50           = -575   3 rows   entries 4, 7, 10
--
--   grand total 425 + 575 - 575 =  425  over 12 rows
SELECT account, SUM(cents), COUNT(*), MIN(entry), MAX(entry)
  FROM ledger
 GROUP BY account
 ORDER BY account;

-- The same reduction over the whole table, which catches a `GROUP BY` that lost
-- or duplicated a row rather than mis-typed one: the three group sums have to add
-- up to it, and the three group counts have to add up to its count.
SELECT 'grand', SUM(cents), COUNT(*) FROM ledger;