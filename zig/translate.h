/* The one header this package translates.
 *
 * `zig build` runs translate-c over this file, and what that translation becomes
 * is the `c` module the Zig facade in zig/root.zig imports.  Its whole job is to
 * name the public header of the library this build compiles.
 *
 * Which header that is
 * --------------------
 * SQLite installs two headers - upstream/main.mk:1613-1614 is
 *
 *     install-headers: sqlite3.h $(install-dir.include)
 *             $(INSTALL.noexec) sqlite3.h "$(TOP)/src/sqlite3ext.h" ...
 *
 * - and this file names one of them:
 *
 *   sqlite3.h  the entire C API.  upstream/README.md:240 says it in prose -
 *              "The SQLite interface is defined by the sqlite3.h header file" -
 *              and src/sqlite3.h:26-31 says it again: "If a C-function,
 *              structure, datatype, or constant definition does not appear in
 *              this file, then it is not a published API of SQLite".
 *
 * It is included whole, with its own include guard, so this wrapper cannot
 * disagree with the real header by omission and cannot re-declare a prototype
 * with a different type.  The translation therefore carries exactly the 366
 * names src/sqlite3.h declares: 365 functions and the data object
 * sqlite3_version (:188).  runtime/graph.zig accounts for all 366.
 *
 * Why sqlite3ext.h is installed and not translated
 * -------------------------------------------------
 * sqlite3ext.h is not an API declaration surface at all.  Its interface is
 * #define macros that redirect every call through one global structure:
 *
 *   - src/sqlite3ext.h:402-736 is one long block of
 *     `#define sqlite3_aggregate_context sqlite3_api->aggregate_context` and so
 *     on, guarded by `#if !defined(SQLITE_CORE) && !defined(SQLITE_OMIT_LOAD_EXTENSION)`.
 *   - The file's own comment at src/sqlite3ext.h:394-400 explains why: the
 *     header is also used by the library's own loadext.c "so that it can get
 *     access to the sqlite3_api_routines structure definition.  But the main
 *     library does not want to redefine the API.  So the redefinition macros
 *     are only valid if the SQLITE_CORE macros is undefined."
 *   - The one symbol those macros need is itself a macro -
 *     SQLITE_EXTENSION_INIT3 at src/sqlite3ext.h:735-737 expands to
 *     `extern const sqlite3_api_routines *sqlite3_api` - and it exists only in
 *     a file actually compiled as a loadable extension.
 *
 * A macro cannot survive into a translation as a declaration, so translating
 * this header would contribute no functions at all.  The alternative would be
 * to define SQLITE_CORE for the translation and take the declaration of
 * sqlite3_api instead, which is worse: this package builds the library, not an
 * extension, and a libsqlite3.so exports no sqlite3_api, so the loader would
 * ask every provider for a symbol no conforming provider has and every load
 * would end in MissingSymbol.  runtime/graph.zig says the same thing where the
 * router is configured.
 *
 * The header is still installed, unchanged, by build.zig, because it is one of
 * upstream's two installed headers and an extension or C consumer of the
 * installed tree needs it exactly as upstream's install provides it.
 *
 * What is deliberately not here
 * -----------------------------
 * A copy of any declaration, and no macro of this build's own.
 *
 * There is no SQLITE_* option on the translate line, and that is the same
 * decision build.zig makes for the C core: this package compiles SQLite's own
 * default configuration, selected by sqlite3.c's own detection
 * (src/sqlite3.c:16538-16548 for the operating system,
 * src/sqlite3.c:15106-15111 for SQLITE_THREADSAFE, src/sqlite3.c:11676-11685 for
 * __wasi__).  Defining an option here and not on the C compile line would give
 * the facade constants the compiled library does not have; defining it on both
 * would be a configuration choice this package does not make.  See build.zig,
 * "No compile options are defined".
 *
 * The one option a shared *consumer* might need is SQLITE_API, and it is not
 * defined here either: src/sqlite3.h:72-74 makes it an empty macro unless the
 * platform's own shared-library convention defines it, and sqlite3.h's own
 * declarations are plain `extern` by default (src/sqlite3.h:71-73).  build.zig
 * records what the delivered artifact was built with, and the installed
 * sqlite3.pc carries the flag a consumer of a shared build needs on its own
 * Cflags line.
 */

#ifndef SQLITE_TRANSLATE_H
#define SQLITE_TRANSLATE_H

#include <sqlite3.h>

#endif /* SQLITE_TRANSLATE_H */
