#!/usr/bin/env bash
# build_standalone_icx.sh — Build chdman with Intel ICX (MSVC ABI, static CRT)
#
# Usage:
#   bash build_standalone_icx.sh <mame-source-dir> [output-dir]
#
# Requirements:
#   Intel oneAPI Base Toolkit (icx/icpx) — https://www.intel.com/content/www/us/en/developer/tools/oneapi/base-toolkit.html
#   Visual Studio 2022 (MSVC headers + libs)
#   Windows SDK 10.0.26100.0
#   MSYS2 make (mingw32-make)
#   cmake + ninja  (for zlib-ng)
#   UASM or ml64   (optional, LZMA ASM decoder)
#
# Vs GCC build:
#   - MSVC ABI (not MinGW): different CRT, different linker (lld-link)
#   - Intel SVML (-fp-model=fast): faster math intrinsics
#   - ICX loop optimisations: advanced vectorizer, inter-procedural opts
#   - zlib-ng rebuilt with ICX (MSVC-ABI static lib in build_icx/)
#   - Requires setting LIB/INCLUDE/PATH env vars for MSVC headers+libs

set -e

MAME_SRC="${1:?ERROR: MAME source directory required.
Usage: bash build_standalone_icx.sh <mame-source-dir> [output-dir]}"
OUTDIR="${2:-$(pwd)/chdman_build_icx}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MAME_SRC="$(realpath "$MAME_SRC")"
OUTDIR="$(realpath -m "$OUTDIR")"

# ---------------------------------------------------------------------------
# Locate Intel oneAPI — detect latest version automatically
# ---------------------------------------------------------------------------
ICX_ONEAPI_DIR="${ICX_ONEAPI_DIR:-C:/Program Files (x86)/Intel/oneAPI/compiler/latest}"
ICX_BIN="${ICX_ONEAPI_DIR}/bin/icx.exe"
ICPX_BIN="${ICX_ONEAPI_DIR}/bin/icpx.exe"

[ -f "$ICX_BIN"  ] || { echo "ERROR: ICX not found at $ICX_BIN"; echo "       Set ICX_ONEAPI_DIR env var to point to oneAPI compiler dir."; exit 1; }
[ -f "$ICPX_BIN" ] || { echo "ERROR: ICPX not found at $ICPX_BIN"; exit 1; }

echo "==> Toolchain: $ICPX_BIN"
"$ICPX_BIN" --version | head -1

# ---------------------------------------------------------------------------
# Locate MSVC + WinSDK (required by ICX linker)
# ---------------------------------------------------------------------------
# Find MSVC version automatically (take latest)
MSVC_BASE="C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC"
MSVC_VER=$(ls "$MSVC_BASE" 2>/dev/null | sort -V | tail -1)
[ -n "$MSVC_VER" ] || { echo "ERROR: MSVC not found under $MSVC_BASE"; exit 1; }
MSVC_DIR="${MSVC_BASE}/${MSVC_VER}"

# Find Windows SDK version automatically (take latest)
WINSDK_BASE="C:/Program Files (x86)/Windows Kits/10/Lib"
WINSDK_VER=$(ls "$WINSDK_BASE" 2>/dev/null | sort -V | tail -1)
[ -n "$WINSDK_VER" ] || { echo "ERROR: Windows SDK not found under $WINSDK_BASE"; exit 1; }

echo "    MSVC   : $MSVC_VER"
echo "    WinSDK : $WINSDK_VER"

# ---------------------------------------------------------------------------
# Set environment variables required by ICX linker (lld-link / link.exe)
# LIB  : semicolon-separated list of .lib search paths (Windows-style)
# INCLUDE : semicolon-separated list of header search paths
# PATH : ICX bin must be present
# ---------------------------------------------------------------------------
ICX_LIB="${ICX_ONEAPI_DIR}/lib"
MSVC_LIB="${MSVC_DIR}/lib/x64"
MSVC_INCLUDE="${MSVC_DIR}/include"
UCRT_LIB="C:/Program Files (x86)/Windows Kits/10/Lib/${WINSDK_VER}/ucrt/x64"
UM_LIB="C:/Program Files (x86)/Windows Kits/10/Lib/${WINSDK_VER}/um/x64"
UCRT_INCLUDE="C:/Program Files (x86)/Windows Kits/10/Include/${WINSDK_VER}/ucrt"
UM_INCLUDE="C:/Program Files (x86)/Windows Kits/10/Include/${WINSDK_VER}/um"
SHARED_INCLUDE="C:/Program Files (x86)/Windows Kits/10/Include/${WINSDK_VER}/shared"

export LIB="${ICX_LIB};${MSVC_LIB};${UCRT_LIB};${UM_LIB}"
export INCLUDE="${MSVC_INCLUDE};${UCRT_INCLUDE};${UM_INCLUDE};${SHARED_INCLUDE}"
export PATH="${ICX_ONEAPI_DIR}/bin:${PATH}"
export ICX_ONEAPI_DIR

echo "    LIB    : ${ICX_LIB};${MSVC_LIB};..."

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
cp "$SCRIPT_DIR/Makefile.standalone.icx" "$OUTDIR/Makefile"
cp "$SCRIPT_DIR/setup_zlibng_icx.sh"     "$OUTDIR/"
cp "$SCRIPT_DIR/README.md"               "$OUTDIR/"
cp "$SCRIPT_DIR/DELTA_OPTIMISATIONS.md"  "$OUTDIR/"

# ---------------------------------------------------------------------------
# Build zlib-ng with ICX (MSVC ABI, produces zlib.lib)
# ---------------------------------------------------------------------------
echo "==> Building zlib-ng (ICX/MSVC) ..."
bash "$OUTDIR/setup_zlibng_icx.sh"

# ---------------------------------------------------------------------------
# Build chdman with ICX
# ---------------------------------------------------------------------------
echo "==> Building chdman (ICX) ..."
cd "$OUTDIR"
JOBS=$(nproc 2>/dev/null || echo 4)

# MSYS2 make preferred (mingw32-make handles Windows paths better than GNU make)
[ -d /c/msys64/mingw64/bin ] && export PATH=/c/msys64/mingw64/bin:$PATH
MAKE_BIN=$(which /c/msys64/mingw64/bin/mingw32-make 2>/dev/null \
        || which mingw32-make 2>/dev/null \
        || echo mingw32-make)

# UASM/ml64 detection for LZMA ASM
if which uasm >/dev/null 2>&1; then
    MAKE_ASM_FLAG="HAVE_LZMA_ASM=1"
    echo "    uasm found — LZMA ASM enabled"
elif [ -f "$MSVC_DIR/../../../bin/Hostx64/x64/ml64.exe" ]; then
    MAKE_ASM_FLAG="HAVE_LZMA_ASM=1"
    echo "    ml64 found — LZMA ASM enabled"
else
    MAKE_ASM_FLAG=""
    echo "    No ASM assembler found — C fallback"
fi

# Pass ICX paths via make variables (handles spaces via quoting)
"$MAKE_BIN" -j"$JOBS" $MAKE_ASM_FLAG \
    "ICX_BIN_DIR=${ICX_ONEAPI_DIR}/bin"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
ICX_VER=$("$ICPX_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "============================================================"
echo " Build complete! (ICX ${ICX_VER}, MSVC ABI)"
echo " Binary : $OUTDIR/chdman.exe"
echo " Test   : cd \"$OUTDIR\" && ./chdman.exe verify -i your.chd"
echo "============================================================"
