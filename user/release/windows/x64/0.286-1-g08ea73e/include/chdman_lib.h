#pragma once

#include <stddef.h>

#if defined(_WIN32)
#  ifdef CHDMAN_BUILDING_DLL
#    define CHDMAN_API __declspec(dllexport)
#  else
#    define CHDMAN_API __declspec(dllimport)
#  endif
#else
#  define CHDMAN_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Runs chdman with the same command-line arguments the chdman CLI takes -- e.g.
 * createcd / extractcd / createdvd / createhd / extracthd / createraw / extractraw /
 * createld / info / verify -- exactly as documented by `chdman help <command>`.
 *
 * argv must NOT include a program name: argv[0] is the command itself (e.g. "createcd"),
 * followed by its options and values (e.g. "-i", "input.cue", "-o", "output.chd").
 * argc is the number of entries in argv. This mirrors invoking:
 *   chdman <argv[0]> <argv[1]> <argv[2]> ...
 * from the command line -- input/output paths and every other chdman option are passed
 * exactly as the CLI would take them, just as function arguments instead of a shell
 * command line.
 *
 * Returns the same exit code the chdman CLI would return (0 = success).
 *
 * All text chdman would normally print to stdout/stderr during the call is captured
 * instead of being written to the real streams. If out_log is non-NULL, *out_log is set
 * to a newly allocated, null-terminated buffer containing that captured text (never
 * NULL, even on success -- may be an empty string). The caller owns this buffer and
 * must release it with chdman_free_log(). Pass NULL for out_log to discard the text.
 *
 * Not safe to call concurrently with itself on multiple threads at once: chdman's
 * command handlers use process-wide state (e.g. the shared CHD compressor thread
 * pool). Serialize calls, e.g. one thread per conversion.
 */
CHDMAN_API int chdman_run(int argc, const char* const* argv, char** out_log);

/* Releases a buffer returned via chdman_run's out_log. Safe to call with NULL. */
CHDMAN_API void chdman_free_log(char* log);

#ifdef __cplusplus
}
#endif
