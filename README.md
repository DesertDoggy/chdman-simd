# CHDMAN_SIMD

SIMD and pipeline optimizations for `chdman` (MAME CHD manager).

Tested on MAME **0.286** — i5-6200U (2 cores / 4 threads HT), Windows 11.
Profiler: Intel VTune Profiler (hotspot sampling, user-mode).

## Results (kinst2.chd, 131 MB, LZMA-dominant)

| Optimization | Impact |
|---|---|
| Multi-thread pipeline (N_SLOTS=3) | −47% spin time |
| FILE_FLAG_SEQUENTIAL_SCAN | ~−3% elapsed |
| CRC16 slice-by-16 | −57% CPU on CRC16 |
| SHA1 SSE2 / SSSE3 / AVX2 / SHA-NI dispatch | 7.3% CPU (SSE2 path), ~2% with SHA-NI |
| LZMA ASM decoder (LzmaDecOpt.asm) | −29% CPU on LZMA |
| zlib-ng AVX2 (inflate) | −76% CPU on inflate |
| **Total vs MAME baseline** | **11.15s → 3.26s = −71%** |

See [`OPTIMISATIONS.md`](OPTIMISATIONS.md) for full VTune measurements, code diffs and rationale.

---

## Patches

Five patches applied to MAME sources (target: MAME 0.286):

| Patch | File | What it does |
|---|---|---|
| `01_chdman_pipeline` | `src/tools/chdman.cpp` | Replaces sequential single-thread loop with a N_SLOTS=3 triple-buffer pipeline using the OSD work queue. SHA1 computed interleaved while data is hot in L1/L2 cache. |
| `02_winfile_sequential` | `src/osd/modules/file/winfile.cpp` | Adds `FILE_FLAG_SEQUENTIAL_SCAN` on read-only CHD opens. Triggers aggressive Windows cache prefetch. |
| `03_hashing_simd` | `src/lib/util/hashing.cpp` | CRC16 slice-by-16 (16 bytes/iter vs 1). SHA1 runtime CPUID dispatch: scalar → SSE2 → SHA-NI (rounds); scalar → SSSE3 → AVX2 (byte-swap). SHA-NI validated against scalar on first call. |
| `04_chdcodec_flac_lzma` | `src/lib/util/chdcodec.cpp` | FLAC: eliminates the 3rd encode pass (LE direct, BE into tmpbuf, memcpy winner). LZMA: `CLzmaEncHandle` kept persistent per compressor instance — no alloc/free per hunk. |
| `05_chd_warning` | `src/lib/util/chd.cpp` | `int codecnum` → `std::size_t` to match `std::size()` return type (eliminates `-Wsign-compare` warning). |

---

## Build methods

### Method A — Patch a full MAME source tree

Apply patches to an existing MAME checkout, then build with the standard MAME build system.

```bash
cd mame0286/
for p in /path/to/CHDMAN_SIMD/patches/0*.patch; do patch -p1 < "$p"; done
make TOOLS=1 chdman -j$(nproc)
```

See [`patches/APPLY_PATCHES.md`](patches/APPLY_PATCHES.md) for conflict resolution and fuzz options.

---

### Method B — Standalone build (Windows / MSYS2)

The standalone scripts copy only the required files from the MAME source tree, apply all patches,
build zlib-ng and produce `chdman.exe` in one command. Three compiler variants available:

#### B1 — GCC / MinGW64 (recommended, widest compatibility)

```bash
pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-make mingw-w64-x86_64-cmake
pacman -S mingw-w64-x86_64-uasm   # optional — enables LZMA ASM decoder

bash build_standalone.sh /path/to/mame0286 [output-dir]
# → output-dir/chdman.exe
```

Binary: statically linked, no runtime dependencies. Runs on any x86-64 Windows.
SIMD paths (SSE2 / SSSE3 / AVX2 / SHA-NI) are compiled in and dispatched at runtime via CPUID.

#### B2 — Clang / LLD (MSYS2, MinGW ABI)

```bash
pacman -S mingw-w64-x86_64-clang mingw-w64-x86_64-lld mingw-w64-x86_64-make
pacman -S mingw-w64-x86_64-cmake mingw-w64-x86_64-uasm   # optional

bash build_standalone_clang.sh /path/to/mame0286 [output-dir]
# → output-dir/chdman.exe
```

Same MinGW ABI as GCC — reuses the same zlib-ng build, same UASM ASM, same binary format.
Uses LLD as linker (~2× faster link than ld.bfd). Clang's autovectorizer can produce tighter
inner loops on some floating-point-heavy code paths.

**Note:** ThinLTO (`-flto=thin`) is intentionally disabled — incompatible with
`--allow-multiple-definition` (required for the LZMA ASM override) and with non-LTO objects
inside `libz.a`.

#### B3 — Intel ICX (MSVC ABI, requires oneAPI + VS 2022)

```bash
# Requirements:
#   Intel oneAPI Base Toolkit (icx/icpx) — https://www.intel.com/content/www/us/en/developer/tools/oneapi/base-toolkit.html
#   Visual Studio 2022 (Community or higher)
#   Windows SDK 10.0.26100.0
#   MSYS2 (for mingw32-make, cmake, ninja, uasm)

bash build_standalone_icx.sh /path/to/mame0286 [output-dir]
# → output-dir/chdman.exe
```

Targets MSVC ABI (`x86_64-pc-windows-msvc`) with static CRT (`-fms-runtime-lib=static`).
zlib-ng is rebuilt with ICX (separate `build_icx/zlib.lib`).
Intel-specific optimizations: `-fp-model=fast` (relaxed FP, enables SVML calls for transcendentals).
ICX's inter-procedural optimizer can perform more aggressive loop transformations than GCC/Clang
on computationally dense sections (LZMA state machine, FLAC LPC).

The script auto-detects MSVC version and Windows SDK version — no manual path configuration needed.

---

### Step 1 — Get the MAME sources (required by all Method B variants)

Download the source archive from the [MAME releases page](https://github.com/mamedev/mame/releases)
(*Source code (zip)* or *Source code (tar.gz)*):

```bash
unzip mame0286s.zip   # → mame-mame0286/
# or
tar xf mame0286s.tar.gz
```

---

## Manual standalone build (step by step)

If you prefer to drive each step yourself instead of using the all-in-one script:

```bash
# 1. Build zlib-ng once (GCC variant)
bash setup_zlibng.sh

# 2a. Portable — SSE2 baseline, SIMD paths dispatched at runtime
mingw32-make -j$(nproc)

# 2b. Native — optimized for the build machine
mingw32-make -j$(nproc) MARCH_BASE="-march=native"

# 3. Verify the binary
./chdman.exe verify -i your.chd
```

---

## Runtime feature banner

The binary prints its active SIMD paths on startup:

```
chdman - MAME Compressed Hunks of Data (CHD) manager 0.286 (unknown)
  [SHA1=SSE2+AVX2  inflate=AVX2  FLAC=AVX2+FMA  LZMA=ASM]
```

| Field | Meaning |
|---|---|
| `SHA1=SSE2+AVX2` | SHA-NI not available on this CPU; using SSE2 rounds + AVX2 byte-swap |
| `SHA1=SHA-NI+AVX2` | Full hardware SHA acceleration (Intel Ice Lake+, AMD Zen+) |
| `inflate=AVX2` | zlib-ng inflate dispatched to AVX2 path |
| `FLAC=AVX2+FMA` | FLAC LPC intrinsics at AVX2+FMA level |
| `LZMA=ASM` | LzmaDecOpt.asm linked and active (LzFindOpt.asm also linked, inactive under `-DZ7_ST`) |

---

## License

Patches modify MAME source files licensed under **BSD-3-Clause**.
Original copyrights (Aaron Giles, Vas Crabb) are preserved in all modified files.
LZMA SDK (`LzmaDecOpt.asm`, `LzFindOpt.asm`): public domain (Igor Pavlov).
zlib-ng: zlib license.

See [`LICENSES.md`](LICENSES.md) for full details.
