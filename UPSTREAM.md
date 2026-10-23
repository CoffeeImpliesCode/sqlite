# Upstream

| Field | Value |
|---|---|
| Project | SQLite, SQL database engine |
| Official site | <https://sqlite.org/> |
| VCS | Fossil, <https://sqlite.org/src/timeline> |
| Release | SQLite 3.53.4, 2026-07-24 |
| Check-in | `bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc` |
| Tag / branch | `version-3.53.4` / `branch-3.53` |
| Check-in time | `2026-07-24T19:02:57.525Z` |
| Source archives | `sqlite-amalgamation-3530400.zip` and `sqlite-src-3530400.zip` |

The check-in appears in `upstream/manifest.uuid` and `src/sqlite3.h`'s `SQLITE_SOURCE_ID`. SHA3-256 of `upstream/manifest`, excluding its final `# Remove this line` comment, is the same check-in. `src/sqlite3.c` names it with an empty changed-file list.

## Imported files

| Archive | Imported path | Files |
|---|---|---:|
| `sqlite-amalgamation-3530400.zip` | `src/` | 4 |
| `sqlite-src-3530400.zip` | `upstream/` | 10 |
| `sqlite-src-3530400.zip` | `test/` | 1,285 |
| **Total** | | **1,299** |

`UPSTREAM.sha256` lists per-file SHA-256 digests for the imported files. Neither archive's SHA-256 is recorded; neither archive file is present in this tree.

## Upstream material not imported

| Upstream path | Status |
|---|---|
| Canonical module-based `src/` tree from `sqlite-src-3530400.zip` | Not imported; the manifest lists 2,205 files. The local `src/` comes from the separate amalgamation archive. |
| `ext/` | Not present in either imported archive. |

The imported upstream files are unchanged.
