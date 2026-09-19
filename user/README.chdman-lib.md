# chdman shared library

Builds chdman (MAME's CHD manager, with chdman-simd's SIMD/pipeline patches) as a single
self-contained shared library instead of the `chdman.exe` CLI, exposing a small C API in
[`chdman_lib.h`](chdman_lib.h) that takes the same arguments the CLI does.

## Output layout
- `user/release/{platform}/{arch}/{version}/dynamic/chdman.dll|libchdman.so|libchdman.dylib`
- `user/release/{platform}/{arch}/{version}/include/chdman_lib.h`
- intermediate objects: `user/_build`

Nothing is ever written outside `user/` -- the `chdman-simd` and `mame` submodule
checkouts stay pristine.

## Build
```bash
user/scripts/build_chdman_lib.sh                  # auto-detect host platform/arch
user/scripts/build_chdman_lib.sh linux x64
user/scripts/build_chdman_lib.sh mac arm64
user/scripts/build_chdman_lib.sh windows x64       # run from an MSYS2 MinGW64 shell
user/scripts/build_chdman_lib.sh android arm64     # requires ANDROID_NDK_HOME
user/scripts/build_chdman_lib.sh ios arm64         # requires Xcode; experimental, see below
```

Requires the `mame` and `zlib-ng` submodules initialized as siblings of `chdman-simd`
under `submodules/`.

### Prerequisites per platform
- **windows**: MSYS2 MinGW64 shell, `pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-make`. Optional: `mingw-w64-x86_64-uasm` for the hand-written LZMA ASM decoder.
- **linux**: gcc/g++, cmake, make.
- **mac**: Xcode command line tools (clang, cmake).
- **android**: Android NDK r26+, `ANDROID_NDK_HOME` set.
- **ios**: Xcode. **Experimental** -- MAME/chdman upstream have no official iOS target; this only works because chdman is a batch CLI tool with no JIT/emulation core, but expect to iterate on real build errors here.

## API
Header: `user/chdman_lib.h`
- `chdman_run(argc, argv, out_log)` -- runs chdman with the same command-line arguments
  the CLI takes (`createcd`, `extractcd`, `createdvd`, `createhd`, `info`, `verify`, ...).
  `argv` excludes the program name: `argv[0]` is the command, followed by its options and
  values, exactly as documented by `chdman help <command>`. Returns the same exit code
  the CLI would. Captured stdout/stderr text is returned via `out_log` (caller frees with
  `chdman_free_log`).
- `chdman_free_log(log)`

Not safe to call concurrently with itself -- chdman's command handlers use process-wide
state (the shared CHD compressor thread pool). Serialize calls.

## Design notes
- `chdman.cpp`'s own `main()` is never modified. It's compiled with `-Dmain=chdman_cli_entry`
  (see `Makefile.chdman_lib`), renaming the entry point at the preprocessor level so the
  wrapper in `chdman_lib.cpp` can call it as an ordinary function while reusing chdman's
  real, unmodified command dispatch (`s_commands[]` lookup, option parsing, error handling).
- On non-Windows platforms, MAME's own `osdlib_unix.cpp`/`osdlib_macosx.cpp` are **not**
  used -- both unconditionally pull in SDL2, which a batch CLI tool never needs.
  `user/osdlib_posix_min.cpp` implements just the handful of `osd_*` symbols chdman's link
  graph actually requires, with zero extra dependencies.
- x64 builds use an SSE2 baseline (portable to all x86-64 CPUs) with AVX2/SHA-NI compiled
  in per-file and selected at runtime via CPUID dispatch (chdman-simd's own patches) --
  never assumed present. arm64 builds use NEON unconditionally (mandatory on AArch64); no
  x86 intrinsics are compiled in.
- All dependencies (LZMA, zstd, expat, utf8proc, FLAC, zlib-ng) are statically linked into
  the one output shared library -- nothing else needs to ship alongside it at runtime.
