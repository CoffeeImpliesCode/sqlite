/* SPDX-License-Identifier: LicenseRef-PublicDomain */

#include <sqlite3.h>

/* Form the copy sentinel in C; it need not satisfy Zig function alignment. */
int sqlite_rt_bind_text_transient(
    int (*bind_text)(sqlite3_stmt *, int, const char *, int, sqlite3_destructor_type),
    sqlite3_stmt *statement, int index, const char *value, int len) {
  return bind_text(statement, index, value, len, SQLITE_TRANSIENT);
}

int sqlite_rt_bind_blob_transient(
    int (*bind_blob)(sqlite3_stmt *, int, const void *, int, sqlite3_destructor_type),
    sqlite3_stmt *statement, int index, const void *value, int len) {
  return bind_blob(statement, index, value, len, SQLITE_TRANSIENT);
}
