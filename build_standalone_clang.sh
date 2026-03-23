#!/usr/bin/env bash
# build_standalone_clang.sh — Build chdman with MSYS2 Clang (MinGW ABI)
#
# Usage:
#   bash build_standalone_clang.sh <mame-source-dir> [output-dir]
#
# Requirements (MSYS2/MinGW64):
#   pacman -S mingw-w64-x86_64-clang mingw-w64-x86_64-lld mingw-w64-x86_64-make
#   pacman -S mingw-w64-x86_64-cmake mingw-w64-x86_64-uasm
#
# Vs GCC build:
#   - LTO thin activé (-flto=thin, réduit taille + meilleure inlining cross-TU)
#   - LLD utilisé comme linker (-fuse-ld=lld, ~2× plus rapide que ld.bfd)
#   - Clang SIMD autovectorizer parfois plus agressif que GCC sur les boucles scalaires
#   - Même ABI MinGW → même zlib-ng, même UASM ASM, même binary format

set -e

MAME_SRC="${1:?ERROR: MAME source directory required.
Usage: bash build_standalone_clang.sh <mame-source-dir> [output-dir]}"
OUTDIR="${2:-$(pwd)/chdman_build_clang}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MAME_SRC="$(realpath "$MAME_SRC")"
OUTDIR="$(realpath -m "$OUTDIR")"

# ---------------------------------------------------------------------------
# MSYS2 Clang toolchain — must be first in PATH
# ---------------------------------------------------------------------------
[ -d /c/msys64/mingw64/bin ] && export PATH=/c/msys64/mingw64/bin:$PATH

CLANGXX=$(which clang++ 2>/dev/null) || { echo "ERROR: clang++ not found. Install mingw-w64-x86_64-clang"; exit 1; }
CLANG=$(which clang 2>/dev/null)     || { echo "ERROR: clang not found."; exit 1; }

echo "==> Toolchain: $CLANGXX"
"$CLANGXX" --version | head -1

# ---------------------------------------------------------------------------
# Validate MAME source tree
# ---------------------------------------------------------------------------
echo "==> Validating MAME source tree: $MAME_SRC"

for f in src/tools/chdman.cpp src/lib/util/hashing.cpp \
          src/osd/modules/file/winfile.cpp; do
    [ -f "$MAME_SRC/$f" ] || { echo "ERROR: $MAME_SRC/$f not found."; exit 1; }
done
for d in 3rdparty/lzma 3rdparty/expat 3rdparty/flac 3rdparty/zstd 3rdparty/utf8proc; do
    [ -d "$MAME_SRC/$d" ] || { echo "ERROR: $MAME_SRC/$d not found."; exit 1; }
done

# ---------------------------------------------------------------------------
# Create output structure
# ---------------------------------------------------------------------------
echo "==> Creating output directory: $OUTDIR"
mkdir -p "$OUTDIR"

# ---------------------------------------------------------------------------
# Copy MAME sources
# ---------------------------------------------------------------------------
echo "==> Copying src/ ..."
cp -r "$MAME_SRC/src" "$OUTDIR/"

if [ ! -f "$OUTDIR/src/version.cpp" ]; then
    if [ -f "$MAME_SRC/build/generated/version.cpp" ]; then
        cp "$MAME_SRC/build/generated/version.cpp" "$OUTDIR/src/version.cpp"
    else
        MAME_VER=$(basename "$MAME_SRC" | grep -oE '[1-9][0-9]{2,3}' | head -1)
        cat > "$OUTDIR/src/version.cpp" <<EOF
#define BARE_BUILD_VERSION "0.${MAME_VER}"
#define BARE_VCS_REVISION "unknown"
extern const char bare_build_version[];
extern const char bare_vcs_revision[];
extern const char build_version[];
const char bare_build_version[] = BARE_BUILD_VERSION;
const char bare_vcs_revision[]  = BARE_VCS_REVISION;
const char build_version[]      = BARE_BUILD_VERSION " (" BARE_VCS_REVISION ")";
EOF
    fi
fi

echo "==> Copying 3rdparty/ ..."
mkdir -p "$OUTDIR/3rdparty"
for lib in lzma utf8proc expat zstd flac aes256cbc nanosvg; do
    [ -d "$MAME_SRC/3rdparty/$lib" ] && cp -r "$MAME_SRC/3rdparty/$lib" "$OUTDIR/3rdparty/"
done

# ---------------------------------------------------------------------------
# Apply patches
# ---------------------------------------------------------------------------
echo "==> Applying patches ..."
cd "$OUTDIR"

for patch in \
    "$SCRIPT_DIR/patches/01_chdman_pipeline.patch" \
    "$SCRIPT_DIR/patches/02_winfile_sequential.patch" \
    "$SCRIPT_DIR/patches/03_hashing_simd.patch" \
    "$SCRIPT_DIR/patches/04_chdcodec_flac_lzma.patch" \
    "$SCRIPT_DIR/patches/05_chd_warning.patch"; do

    name="$(basename "$patch")"
    if patch -p1 --dry-run < "$patch" >/dev/null 2>&1; then
        patch -p1 < "$patch"
        echo "    [OK] $name"
    else
        echo "    [WARN] $name failed dry-run — attempting with --fuzz=5"
        if patch -p1 --fuzz=5 < "$patch" 2>/dev/null; then
            echo "    [OK] $name (with fuzz)"
        else
            echo "    [FAIL] $name — manual merge required."
            echo "WARNING: patch $name was NOT applied. Binary will be incomplete." >&2
        fi
    fi
done

# ---------------------------------------------------------------------------
# Copy build files
# ---------------------------------------------------------------------------
echo "==> Copying Makefile and setup script ..."
cp "$SCRIPT_DIR/Makefile.standalone" "$OUTDIR/Makefile"
cp "$SCRIPT_DIR/setup_zlibng.sh"     "$OUTDIR/"
cp "$SCRIPT_DIR/README.md"           "$OUTDIR/"
cp "$SCRIPT_DIR/DELTA_OPTIMISATIONS.md" "$OUTDIR/"

# ---------------------------------------------------------------------------
# Build zlib-ng (same MinGW ABI as GCC — reuse if already built)
# ---------------------------------------------------------------------------
echo "==> Building zlib-ng ..."
bash "$OUTDIR/setup_zlibng.sh"

# ---------------------------------------------------------------------------
# Build chdman with Clang
# ---------------------------------------------------------------------------
echo "==> Building chdman (Clang) ..."
cd "$OUTDIR"
JOBS=$(nproc 2>/dev/null || echo 4)
MAKE_BIN=$(which /c/msys64/mingw64/bin/mingw32-make 2>/dev/null \
        || which mingw32-make 2>/dev/null \
        || echo mingw32-make)

# UASM detection
if which uasm >/dev/null 2>&1; then
    MAKE_ASM_FLAG="HAVE_LZMA_ASM=1"
    echo "    uasm found — LZMA ASM enabled"
else
    MAKE_ASM_FLAG=""
    echo "    uasm not found — C fallback"
fi

# Clang-specific flags:
#   -fuse-ld=lld        : LLD linker (faster, better ICF/dedup)
#   -flto=thin          : ThinLTO (cross-TU inlining, fast)
#   -Wno-unused-command-line-argument : clang warning on GCC-isms
# Note: -flto=thin incompatible avec --allow-multiple-definition (LZMA ASM)
# et avec les objets libz.a non-LTO. LLD seul suffit (+link plus rapide).
CLANG_EXTRA="-fuse-ld=lld -Wno-unused-command-line-argument"

"$MAKE_BIN" -j"$JOBS" $MAKE_ASM_FLAG \
    CXX="$CLANGXX" \
    CC="$CLANG" \
    EXTRA_CXXFLAGS="$CLANG_EXTRA" \
    EXTRA_CFLAGS="$CLANG_EXTRA"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " Build complete! (Clang $(${CLANGXX} --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1))"
echo " Binary : $OUTDIR/chdman.exe"
echo " Test   : cd \"$OUTDIR\" && ./chdman.exe verify -i your.chd"
echo "============================================================"
