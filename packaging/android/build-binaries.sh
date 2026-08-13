#!/usr/bin/env bash
# Сборка бинарников wworld под Android arm64 готовым кросс-компилятором.
#   packaging/android/build-binaries.sh [каталог назначения]
set -euo pipefail

PREFIX="${PREFIX:-/opt}"
NDK_VERSION="${NDK_VERSION:-r26d}"
API="${API:-21}"
OUT="${1:-build/android/arm64-v8a}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FPCA="$PREFIX/fpc-src/compiler/ppcrossa64"
RTL="$PREFIX/fpc-src/rtl/units/aarch64-android"
SYSROOT="$PREFIX/android-ndk-$NDK_VERSION/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
PKG=$(find "$PREFIX/fpc-src/packages" -type d -name "aarch64-android" | sed 's/^/-Fu/' | tr '\n' ' ')

mkdir -p "$OUT" build/android/units
for prog in demo:wworld wwwalk:wwwalk; do
  src="${prog%%:*}"; name="${prog##*:}"
  echo "== $name =="
  PATH="$PREFIX/ndkbin:$PATH" "$FPCA" -Tandroid -Paarch64 -Mobjfpc -Sh -O2 \
    -Fu"$RTL" $PKG -Fusrc/dungeon -FUbuild/android/units \
    -Fl"$SYSROOT/usr/lib/aarch64-linux-android/$API" \
    -Fl"$SYSROOT/usr/lib/aarch64-linux-android" \
    -FD"$PREFIX/ndkbin" -o"$OUT/$name" "src/demo/$src.pas"
  file "$OUT/$name" | cut -c1-100
done
