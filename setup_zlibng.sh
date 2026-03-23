#!/usr/bin/env bash
# setup_zlibng.sh — Download and build zlib-ng 2.3.3 (ZLIB_COMPAT mode)
# Run once from CHDMAN_SIMD/ before first build
# Requires: cmake, mingw32-make (MSYS2/MinGW64)

set -e

ZLIBNG_VERSION=2.3.3
ZLIBNG_URL="https://github.com/zlib-ng/zlib-ng/archive/refs/tags/${ZLIBNG_VERSION}.tar.gz"
ZLIBNG_DIR="$(pwd)/3rdparty_extra/zlib-ng-${ZLIBNG_VERSION}"
BUILD_DIR="${ZLIBNG_DIR}/build"

if [ -f "${BUILD_DIR}/libz.a" ]; then
    echo "zlib-ng already built at ${BUILD_DIR}/libz.a — skipping."
    exit 0
fi

echo "==> Downloading zlib-ng ${ZLIBNG_VERSION}..."
mkdir -p "$(pwd)/3rdparty_extra"
curl -L "${ZLIBNG_URL}" -o "/tmp/zlib-ng-${ZLIBNG_VERSION}.tar.gz"
tar -xzf "/tmp/zlib-ng-${ZLIBNG_VERSION}.tar.gz" -C "$(pwd)/3rdparty_extra"

echo "==> Building zlib-ng (ZLIB_COMPAT=ON)..."
mkdir -p "${BUILD_DIR}"
cmake -S "${ZLIBNG_DIR}" -B "${BUILD_DIR}" \
    -G "MinGW Makefiles" \
    -DZLIB_COMPAT=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DZLIB_ENABLE_TESTS=OFF \
    -DWITH_GTEST=OFF \
    -DCMAKE_C_FLAGS="-O3 -march=native"
cmake --build "${BUILD_DIR}" -- -j$(nproc)

echo "==> Done: ${BUILD_DIR}/libz.a"
echo "    Header: ${BUILD_DIR}/zlib.h"
