# CHDMAN_SIMD — Applying the patches

## Available patches

| # | Patch file | Target file | Effect |
|---|---|---|---|
| 01 | `01_chdman_pipeline.patch` | `src/tools/chdman.cpp` | N_SLOTS=3 triple-buffer pipeline, interleaved SHA1 |
| 02 | `02_winfile_sequential.patch` | `src/osd/modules/file/winfile.cpp` | `FILE_FLAG_SEQUENTIAL_SCAN` (Windows, read-only paths) |
| 03 | `03_hashing_simd.patch` | `src/lib/util/hashing.cpp` | CRC16 slice-by-16, SHA1 SSE2 + SSSE3 + AVX2 + SHA-NI dispatch |
| 04 | `04_chdcodec_flac_lzma.patch` | `src/lib/util/chdcodec.cpp` | FLAC 3→2 encodes (memcpy instead of re-encode), LZMA persistent encoder |
| 05 | `05_chd_warning.patch` | `src/lib/util/chd.cpp` | Sign-compare warning fix (`int` → `size_t`) |

## Compatibility

Generated from MAME **0.286**. Tested on 0.286.
Compatible with 0.287+ provided `do_verify`, `crc16_creator::append`, and `winfile_open` have not changed.

```bash
# Dry-run before applying
cd mame287sources/
patch -p1 --dry-run < /path/to/CHDMAN_SIMD/patches/01_chdman_pipeline.patch
patch -p1 --dry-run < /path/to/CHDMAN_SIMD/patches/02_winfile_sequential.patch
patch -p1 --dry-run < /path/to/CHDMAN_SIMD/patches/03_hashing_simd.patch
patch -p1 --dry-run < /path/to/CHDMAN_SIMD/patches/04_chdcodec_flac_lzma.patch
patch -p1 --dry-run < /path/to/CHDMAN_SIMD/patches/05_chd_warning.patch
```

## Applying — full MAME source tree

From the **MAME repository root**:

```bash
cd mame287sources/   # or mame286sources/, etc.

patch -p1 < /path/to/CHDMAN_SIMD/patches/01_chdman_pipeline.patch
patch -p1 < /path/to/CHDMAN_SIMD/patches/02_winfile_sequential.patch
patch -p1 < /path/to/CHDMAN_SIMD/patches/03_hashing_simd.patch
patch -p1 < /path/to/CHDMAN_SIMD/patches/04_chdcodec_flac_lzma.patch
patch -p1 < /path/to/CHDMAN_SIMD/patches/05_chd_warning.patch
```

Build chdman only:
```bash
make TOOLS=1 chdman -j$(nproc)
```

## Applying — standalone build

See `Makefile.standalone` at the project root.
Patch 03 does not apply to the standalone: `hashing.SSE2.cpp` already contains the modified version.

```bash
# Full standalone build
mingw32-make -j8
```

## Conflict resolution

If hunks are rejected (`.rej` files created):

- **01** → locate `do_verify` in `chdman.cpp`, find the `for (uint64_t hunknum = 0` loop
- **02** → locate `CreateFileW` in `winfile.cpp`, find the `DWORD fileflags` block
- **03** → locate `crc16_creator::append` in `hashing.cpp`, find the `while (length-- != 0)` loop
- **04** → locate `chd_flac_compressor::compress` and `chd_lzma_compressor` in `chdcodec.cpp`
- **05** → locate `for (int codecnum` in `chd.cpp`

Fuzzy matching as a last resort:
```bash
patch -p1 --fuzz=5 < patches/01_chdman_pipeline.patch
```
