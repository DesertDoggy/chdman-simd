#!/usr/bin/env bash
# setup_zlibng_icx.sh — Build zlib-ng with Intel ICX (MSVC ABI, static CRT)
# Run once from the ICX standalone output directory before first build.
#
# Produces: 3rdparty_extra/zlib-ng-2.3.3/build_icx/zlib.lib  (MSVC .lib format)
#
# Requires: ICX, cmake, ninja (or NMake via VS)

set -e

ICX_ONEAPI_DIR="${ICX_ONEAPI_DIR:-C:/Program Files (x86)/Intel/oneAPI/compiler/latest}"
ICX_BIN="${ICX_ONEAPI_DIR}/bin/icx.exe"
LLVM_AR="${ICX_ONEAPI_DIR}/bin/compiler/llvm-ar.exe"

[ -f "$ICX_BIN"  ] || { echo "ERROR: ICX not found at $ICX_BIN";  exit 1; }
[ -f "$LLVM_AR"  ] || { echo "ERROR: llvm-ar not found at $LLVM_AR"; exit 1; }

# Set LIB / INCLUDE for ICX linker (mirrors build_standalone_icx.sh)
MSVC_BASE="C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC"
MSVC_VER=$(ls "$MSVC_BASE" 2>/dev/null | sort -V | tail -1)
WINSDK_LIB_BASE="C:/Program Files (x86)/Windows Kits/10/Lib"
WINSDK_VER_LIB=$(ls "$WINSDK_LIB_BASE" 2>/dev/null | sort -V | tail -1)
if [ -n "$MSVC_VER" ] && [ -n "$WINSDK_VER_LIB" ]; then
    export LIB="${ICX_ONEAPI_DIR}/lib;${MSVC_BASE}/${MSVC_VER}/lib/x64;${WINSDK_LIB_BASE}/${WINSDK_VER_LIB}/ucrt/x64;${WINSDK_LIB_BASE}/${WINSDK_VER_LIB}/um/x64"
fi

ZLIBNG_VERSION=2.3.3
ZLIBNG_URL="https://github.com/zlib-ng/zlib-ng/archive/refs/tags/${ZLIBNG_VERSION}.tar.gz"
ZLIBNG_DIR="$(pwd)/3rdparty_extra/zlib-ng-${ZLIBNG_VERSION}"
BUILD_DIR="${ZLIBNG_DIR}/build_icx"

if [ -f "${BUILD_DIR}/zlib.lib" ]; then
    echo "zlib-ng (ICX) already built at ${BUILD_DIR}/zlib.lib — skipping."
    exit 0
fi

# Download if not present (share tarball with the GCC setup_zlibng.sh)
if [ ! -d "$ZLIBNG_DIR" ]; then
    echo "==> Downloading zlib-ng ${ZLIBNG_VERSION}..."
    mkdir -p "$(pwd)/3rdparty_extra"
    curl -L "${ZLIBNG_URL}" -o "/tmp/zlib-ng-${ZLIBNG_VERSION}.tar.gz"
    tar -xzf "/tmp/zlib-ng-${ZLIBNG_VERSION}.tar.gz" -C "$(pwd)/3rdparty_extra"
fi

echo "==> Building zlib-ng ${ZLIBNG_VERSION} with ICX (MSVC ABI, static CRT)..."
mkdir -p "${BUILD_DIR}"

# ICX compile flags: static MSVC CRT, no debug, portable x86-64
ICX_C_FLAGS="-O3 -march=x86-64 -msse2 -fms-runtime-lib=static"

# Add WinSDK bin to PATH so cmake/ninja can find rc.exe (required for MSVC-like linking)
WINSDK_VER=$(ls "C:/Program Files (x86)/Windows Kits/10/Lib" 2>/dev/null | sort -V | tail -1)
WINSDK_BIN="C:/Program Files (x86)/Windows Kits/10/bin/${WINSDK_VER}/x64"
RC_EXE="${WINSDK_BIN}/rc.exe"
[ -f "${RC_EXE}" ] && export PATH="${WINSDK_BIN}:${PATH}"

# Prefer Ninja if available, fall back to NMake
if which ninja >/dev/null 2>&1; then
    CMAKE_GENERATOR="Ninja"
    BUILD_CMD="ninja -C ${BUILD_DIR}"
else
    CMAKE_GENERATOR="NMake Makefiles"
    NMAKE=$(find "C:/Program Files/Microsoft Visual Studio" -name "nmake.exe" 2>/dev/null | head -1)
    [ -n "$NMAKE" ] || { echo "ERROR: neither ninja nor nmake found"; exit 1; }
    BUILD_CMD="\"$NMAKE\" -C ${BUILD_DIR}"
fi

cmake -S "${ZLIBNG_DIR}" -B "${BUILD_DIR}" \
    -G "${CMAKE_GENERATOR}" \
    -DCMAKE_C_COMPILER="${ICX_BIN}" \
    -DCMAKE_AR="${LLVM_AR}" \
    -DCMAKE_RC_COMPILER="${RC_EXE}" \
    -DZLIB_COMPAT=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DZLIB_ENABLE_TESTS=OFF \
    -DWITH_GTEST=OFF \
    -DCMAKE_C_FLAGS="${ICX_C_FLAGS}" \
    -DCMAKE_BUILD_TYPE=Release

cmake --build "${BUILD_DIR}" -- -j$(nproc 2>/dev/null || echo 4)

# Rename to zlib.lib regardless of cmake output name
for candidate in libz.a zlibstatic.lib zlib-ng.lib; do
    if [ -f "${BUILD_DIR}/${candidate}" ] && [ ! -f "${BUILD_DIR}/zlib.lib" ]; then
        cp "${BUILD_DIR}/${candidate}" "${BUILD_DIR}/zlib.lib"
        break
    fi
done

[ -f "${BUILD_DIR}/zlib.lib" ] || { echo "ERROR: zlib.lib not produced."; exit 1; }

echo "==> Done: ${BUILD_DIR}/zlib.lib"
