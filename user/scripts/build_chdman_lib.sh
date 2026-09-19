#!/usr/bin/env bash
set -euo pipefail

# Builds chdman as a shared library (chdman.dll / libchdman.so / libchdman.dylib) for one
# platform/arch target, with chdman-simd's SIMD/pipeline patches applied and every
# dependency (LZMA, zstd, expat, utf8proc, FLAC, zlib-ng) statically linked in.
#
# All build output lives under this submodule's own user/ directory -- nothing is ever
# written into the mame/ or chdman-simd repo trees themselves, so both stay pristine
# submodule checkouts.
#
# Usage:
#   user/scripts/build_chdman_lib.sh                      # auto-detect host platform/arch
#   user/scripts/build_chdman_lib.sh <platform> <arch>
#
# Targets:
#   windows/x64   linux/x64   mac/arm64   android/arm64   ios/arm64
#
# Cross-compiling (android/ios, or windows/linux from a different host) requires the
# right toolchain already installed -- see the per-platform notes below and
# user/docs/README.chdman-lib.md.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
user_dir="$(cd "$script_dir/.." && pwd)"
submodule_root="$(cd "$user_dir/.." && pwd)"
submodules_root="$(cd "$submodule_root/.." && pwd)"
mame_src="$submodules_root/mame"
zlibng_src="$submodules_root/zlib-ng"

if [[ ! -f "$mame_src/src/tools/chdman.cpp" ]]; then
  echo "[ERROR] MAME source not found at: $mame_src" >&2
  echo "[ERROR] Expected the 'mame' submodule at submodules/mame (sibling of chdman-simd)." >&2
  exit 2
fi
if [[ ! -d "$zlibng_src" ]]; then
  echo "[ERROR] zlib-ng source not found at: $zlibng_src" >&2
  exit 2
fi

if [[ $# -eq 0 ]]; then
  os_name="$(uname -s)"
  cpu_name="$(uname -m)"
  case "$os_name" in
    Darwin) platform="mac" ;;
    Linux) platform="linux" ;;
    MINGW*|MSYS*|CYGWIN*) platform="windows" ;;
    *) echo "[ERROR] Unsupported OS for auto-detect: $os_name" >&2; exit 2 ;;
  esac
  case "$cpu_name" in
    arm64|aarch64) arch="arm64" ;;
    x86_64|amd64) arch="x64" ;;
    *) echo "[ERROR] Unsupported arch for auto-detect: $cpu_name" >&2; exit 2 ;;
  esac
elif [[ $# -eq 2 ]]; then
  platform="$1"
  arch="$2"
else
  echo "[ERROR] Usage: $0 OR $0 <platform> <arch>" >&2
  exit 2
fi

case "$platform/$arch" in
  windows/x64|linux/x64|mac/arm64|android/arm64|ios/arm64) ;;
  *)
    echo "[ERROR] Unsupported platform/arch combination: $platform/$arch" >&2
    echo "[ERROR] Supported: windows/x64 linux/x64 mac/arm64 android/arm64 ios/arm64" >&2
    exit 2
    ;;
esac

# ---------------------------------------------------------------------------
# chdman-simd's own version tag (e.g. "0.286-1-g08ea73e") -- used only for the release
# output path; harmless if git describe is unavailable (falls back to "dev").
# ---------------------------------------------------------------------------
version="$(git -C "$submodule_root" describe --tags 2>/dev/null || echo dev)"

log_dir="$user_dir/logs"
mkdir -p "$log_dir"
log_file="$log_dir/build-chdman-$platform-$arch-$(date +%Y%m%d-%H%M%S).log"

echo "[INFO] platform=$platform arch=$arch version=$version" | tee -a "$log_file"

# ---------------------------------------------------------------------------
# Toolchain selection per target
# ---------------------------------------------------------------------------
MARCH_EXTRA=""
HAVE_LZMA_ASM=0

case "$platform" in
  windows)
    CC=gcc
    CXX=g++
    AR=ar
    if ! command -v "$CXX" >/dev/null 2>&1; then
      echo "[ERROR] g++ not found. Run from an MSYS2 MinGW64 shell (pacman -S mingw-w64-x86_64-gcc)." >&2
      exit 3
    fi
    # Different UASM distributions name the binary differently (uasm.exe vs the
    # UEFI-targeted build's uasm64.exe) -- check all known names. MSYS2's MinGW64
    # shell launches with a deliberately minimal PATH (no C:\ tool directories), so
    # also check common install locations directly even when PATH doesn't have them.
    UASM_BIN=""
    for candidate in uasm64 uasm64.exe uasm uasm.exe; do
      if command -v "$candidate" >/dev/null 2>&1; then
        UASM_BIN="$(command -v "$candidate")"
        break
      fi
    done
    if [[ -z "$UASM_BIN" ]]; then
      for candidate in "/c/uasm/uasm64.exe" "${UASM_HOME:-}/uasm64.exe" "/c/uasm/uasm.exe"; do
        if [[ -n "$candidate" && -f "$candidate" ]]; then
          UASM_BIN="$candidate"
          break
        fi
      done
    fi
    if [[ -n "$UASM_BIN" ]]; then
      HAVE_LZMA_ASM=1
      echo "[INFO] uasm found at $UASM_BIN -- LZMA ASM decoder enabled" | tee -a "$log_file"
    else
      echo "[INFO] uasm not found on PATH -- LZMA ASM decoder disabled (C fallback)" | tee -a "$log_file"
    fi
    ;;
  linux)
    CC="${CC:-gcc}"
    CXX="${CXX:-g++}"
    AR="${AR:-ar}"
    ;;
  mac)
    CC=clang
    CXX=clang++
    AR=ar
    MARCH_EXTRA="-arch arm64"
    ;;
  android)
    : "${ANDROID_NDK_HOME:?[ERROR] ANDROID_NDK_HOME must point to an installed Android NDK (r26+)}"
    host_tag=""
    case "$(uname -s)" in
      Darwin) host_tag="darwin-x86_64" ;;
      Linux) host_tag="linux-x86_64" ;;
      MINGW*|MSYS*|CYGWIN*) host_tag="windows-x86_64" ;;
    esac
    ndk_bin="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$host_tag/bin"
    android_api=21
    CC="$ndk_bin/aarch64-linux-android${android_api}-clang"
    CXX="$ndk_bin/aarch64-linux-android${android_api}-clang++"
    AR="$ndk_bin/llvm-ar"
    [[ -x "$CC" ]] || { echo "[ERROR] NDK clang not found: $CC" >&2; exit 3; }
    ;;
  ios)
    command -v xcrun >/dev/null 2>&1 || { echo "[ERROR] xcrun not found (requires Xcode)" >&2; exit 3; }
    sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
    CC="xcrun --sdk iphoneos clang"
    CXX="xcrun --sdk iphoneos clang++"
    AR=ar
    MARCH_EXTRA="-arch arm64 -isysroot $sdk_path -mios-version-min=13.0"
    echo "[WARN] iOS target is experimental -- Dolphin/MAME upstream have no official" | tee -a "$log_file"
    echo "[WARN] iOS support; this is chdman only (no JIT/emulation core needed)." | tee -a "$log_file"
    ;;
esac

# ---------------------------------------------------------------------------
# Scratch source copy: MAME src/ + curated 3rdparty/, with chdman-simd's patches
# applied. Lives entirely under user/_build -- never touches mame/ or chdman-simd/'s
# own tracked files.
# ---------------------------------------------------------------------------
src_copy="$user_dir/_build/$platform/$arch/src"
rm -rf "$src_copy"
mkdir -p "$src_copy"

echo "[INFO] Copying MAME src/ ..." | tee -a "$log_file"
cp -r "$mame_src/src" "$src_copy/"

if [[ ! -f "$src_copy/src/version.cpp" ]]; then
  if [[ -f "$mame_src/build/generated/version.cpp" ]]; then
    cp "$mame_src/build/generated/version.cpp" "$src_copy/src/version.cpp"
  else
    mame_ver="$(basename "$(git -C "$mame_src" describe --tags 2>/dev/null || echo mame0000)" | grep -oE '[0-9]{3,4}' | head -1)"
    mame_ver="${mame_ver:-0000}"
    cat > "$src_copy/src/version.cpp" <<EOF
#define BARE_BUILD_VERSION "0.${mame_ver}"
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

echo "[INFO] Copying 3rdparty/ ..." | tee -a "$log_file"
mkdir -p "$src_copy/3rdparty"
for lib in lzma utf8proc expat zstd flac aes256cbc nanosvg; do
  if [[ -d "$mame_src/3rdparty/$lib" ]]; then
    cp -r "$mame_src/3rdparty/$lib" "$src_copy/3rdparty/"
  fi
done

echo "[INFO] Copying wrapper sources (user/chdman_lib.*, user/osdlib_posix_min.cpp) ..." | tee -a "$log_file"
mkdir -p "$src_copy/user"
cp "$user_dir/chdman_lib.h" "$user_dir/chdman_lib.cpp" "$user_dir/osdlib_posix_min.cpp" "$src_copy/user/"

echo "[INFO] Applying chdman-simd patches ..." | tee -a "$log_file"
cd "$src_copy"
for patch in "$submodule_root"/patches/0*.patch; do
  name="$(basename "$patch")"
  if patch -p1 --dry-run < "$patch" >/dev/null 2>&1; then
    patch -p1 < "$patch"
    echo "    [OK] $name" | tee -a "$log_file"
  elif patch -p1 --fuzz=5 --dry-run < "$patch" >/dev/null 2>&1; then
    patch -p1 --fuzz=5 < "$patch"
    echo "    [OK] $name (with fuzz)" | tee -a "$log_file"
  else
    echo "    [FAIL] $name -- manual merge required (see chdman-simd/patches/APPLY_PATCHES.md)" | tee -a "$log_file"
    exit 4
  fi
done

# ---------------------------------------------------------------------------
# zlib-ng (ZLIB_COMPAT=ON), built once per platform/arch from the zlib-ng submodule.
# ---------------------------------------------------------------------------
zlibng_build="$user_dir/_build/$platform/$arch/zlib-ng"
zlibng_lib="$zlibng_build/libz.a"

if [[ ! -f "$zlibng_lib" ]]; then
  echo "[INFO] Building zlib-ng ..." | tee -a "$log_file"
  cmake_generator="Unix Makefiles"
  [[ "$platform" == "windows" ]] && cmake_generator="MinGW Makefiles"

  cmake_extra_args=()
  case "$platform" in
    mac)
      cmake_extra_args+=(-DCMAKE_OSX_ARCHITECTURES=arm64)
      ;;
    ios)
      cmake_extra_args+=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64
        -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0)
      ;;
    android)
      cmake_extra_args+=(-DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
        -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-21)
      ;;
  esac

  cmake -S "$zlibng_src" -B "$zlibng_build" -G "$cmake_generator" \
    -DZLIB_COMPAT=ON -DBUILD_SHARED_LIBS=OFF -DZLIB_ENABLE_TESTS=OFF -DWITH_GTEST=OFF \
    -DCMAKE_C_FLAGS="-O3 $MARCH_EXTRA" \
    "${cmake_extra_args[@]}" 2>&1 | tee -a "$log_file"
  cmake --build "$zlibng_build" -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)" 2>&1 | tee -a "$log_file"
fi

[[ -f "$zlibng_lib" ]] || { echo "[ERROR] zlib-ng build did not produce $zlibng_lib" >&2; exit 5; }

# ---------------------------------------------------------------------------
# Build chdman shared library
# ---------------------------------------------------------------------------
build_obj_dir="$user_dir/_build/$platform/$arch/obj"
out_dir="$user_dir/release/$platform/$arch/$version/dynamic"
include_dir="$user_dir/release/$platform/$arch/$version/include"
mkdir -p "$out_dir" "$include_dir"

echo "[INFO] Building chdman ($platform/$arch) ..." | tee -a "$log_file"
cd "$src_copy"
make -f "$user_dir/Makefile.chdman_lib" \
  PLATFORM="$platform" ARCH="$arch" \
  CC="$CC" CXX="$CXX" AR="$AR" \
  MARCH_EXTRA="$MARCH_EXTRA" \
  HAVE_LZMA_ASM="$HAVE_LZMA_ASM" \
  UASM_BIN="${UASM_BIN:-}" \
  ZLIBNG_BUILD="$zlibng_build" \
  BUILDDIR="$build_obj_dir" \
  -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)" 2>&1 | tee -a "$log_file"

case "$platform" in
  windows) built_name="chdman.dll" ;;
  mac|ios) built_name="libchdman.dylib" ;;
  *) built_name="libchdman.so" ;;
esac

[[ -f "$src_copy/$built_name" ]] || { echo "[ERROR] Build did not produce $src_copy/$built_name" | tee -a "$log_file"; exit 6; }

cp -f "$src_copy/$built_name" "$out_dir/$built_name"
cp -f "$user_dir/chdman_lib.h" "$include_dir/chdman_lib.h"

echo "" | tee -a "$log_file"
echo "[INFO] Build complete." | tee -a "$log_file"
echo "[INFO] Library : $out_dir/$built_name" | tee -a "$log_file"
echo "[INFO] Header  : $include_dir/chdman_lib.h" | tee -a "$log_file"
