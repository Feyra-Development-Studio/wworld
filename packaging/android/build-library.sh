#!/usr/bin/env bash
#
# Сборка игры общей библиотекой под Android.
#
#   packaging/android/build-library.sh <abi> [каталог назначения]
#
#   abi: arm64-v8a  — то, на чём играют
#        x86_64     — то, на чём проверяют (эмулятор)
#
# Приложение на Android не запускает исполняемых файлов: система загружает
# общую библиотеку и зовёт из неё. Поэтому та же игра, что на настольных
# платформах собирается программой, здесь собирается библиотекой с точками
# входа (src/android/wwandroid.pas).
#
# Разница между двумя ABI не только в имени. Для arm64 нужен целый
# кросс-компилятор: на бегунке процессор x86_64, и породить код для другой
# архитектуры родной ppcx64 не может. Для x86_64 архитектура та же, и хватает
# библиотеки времени выполнения, собранной под android — компилятор годится
# родной. Второй путь на порядок быстрее, поэтому проверка на эмуляторе не
# ждёт сборки компилятора.
set -euo pipefail

ABI="${1:?нужен abi: arm64-v8a или x86_64}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PREFIX="${PREFIX:-/opt}"
NDK_VERSION="${NDK_VERSION:-r26d}"
# API 28 — та же планка, что у приложения; её задал Renjin, которому нужен
# API 28, чтобы дексоваться без предупреждений.
API="${API:-28}"
NDK="$PREFIX/android-ndk-$NDK_VERSION"
NDKBIN="$PREFIX/ndkbin-$ABI"
FPCSRC="$PREFIX/fpc-src"
OUT="${2:-build/android/$ABI}"

case "$ABI" in
    arm64-v8a) CPU=aarch64; TRIPLE=aarch64-linux-android; LIBDIR=aarch64-linux-android ;;
    x86_64)    CPU=x86_64;  TRIPLE=x86_64-linux-android;  LIBDIR=x86_64-linux-android ;;
    *) echo "неизвестный abi: $ABI"; exit 2 ;;
esac

echo "== NDK =="
if [ ! -d "$NDK" ]; then
    curl -sL "https://dl.google.com/android/repository/android-ndk-$NDK_VERSION-linux.zip" -o /tmp/ndk.zip
    unzip -q /tmp/ndk.zip -d "$PREFIX"
fi
TOOLS="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"

echo "== обёртки инструментов =="
mkdir -p "$NDKBIN"
ln -sf "$TOOLS/llvm-ar" "$NDKBIN/$TRIPLE-ar"
ln -sf "$TOOLS/llvm-strip" "$NDKBIN/$TRIPLE-strip"
# FPC 3.2.2 порождает скрипт линковки, который lld отвергает, а GNU ld из NDK
# начиная с r23 убран. Берём ld из binutils для той же архитектуры.
if [ "$CPU" = "aarch64" ]; then
    ln -sf "$(command -v aarch64-linux-gnu-ld)" "$NDKBIN/$TRIPLE-ld"
else
    ln -sf "$(command -v ld)" "$NDKBIN/$TRIPLE-ld"
fi

# FPC зовёт ассемблер по имени <префикс>as и передаёт ключи в стиле GNU as.
# В NDK ассемблирует clang, поэтому обёртка переводит --defsym X=Y в
# -Wa,-defsym,X=Y (с одним дефисом — двойной clang не берёт) и помечает вход
# как ассемблерный: расширение .as clang не узнаёт.
cat > "$NDKBIN/$TRIPLE-as" <<EOF
#!/bin/sh
CLANG=$TOOLS/$TRIPLE$API-clang
args=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --defsym) args="\$args -Wa,-defsym,\$2"; shift 2 ;;
    *) args="\$args \$1"; shift ;;
  esac
done
exec \$CLANG -x assembler -c \$args
EOF
chmod +x "$NDKBIN/$TRIPLE-as"

echo "== исходники FPC =="
# Исходники из пакета fpc-source урезаны: в них нет makefile.cpu, без которого
# сборка не идёт. Берём нетронутые.
[ -d "$FPCSRC" ] || git clone -q --depth 1 --branch release_3_2_2 \
    https://github.com/fpc/FPCSource.git "$FPCSRC"

RTL="$FPCSRC/rtl/units/$CPU-android"
# Одного ядра мало: игра берёт Contnrs и SysUtils из пакетов fcl. Признаком
# готовности считаем именно пакеты — ядро без них собирается, а игра нет.
if [ ! -d "$FPCSRC/packages/fcl-base/units/$CPU-android" ]; then
    echo "== библиотека времени выполнения под $CPU-android =="
    cd "$FPCSRC"
    if [ "$CPU" = "$(uname -m)" ]; then
        # Та же архитектура: хватает RTL, компилятор берём родной.
        PATH="$NDKBIN:$PATH" make -s rtl packages \
            CPU_TARGET="$CPU" OS_TARGET=android \
            CROSSBINDIR="$NDKBIN" BINUTILSPREFIX="$TRIPLE-" \
            FPC="$(command -v ppcx64)"
    else
        # Другая архитектура: нужен кросс-компилятор целиком.
        PATH="$NDKBIN:$PATH" make -s crossall \
            CPU_TARGET="$CPU" OS_TARGET=android \
            CROSSBINDIR="$NDKBIN" BINUTILSPREFIX="$TRIPLE-" \
            FPC="$(command -v ppcx64)"
    fi
    cd "$ROOT"
fi

if [ "$CPU" = "$(uname -m)" ]; then
    COMPILER="$(command -v ppcx64)"
else
    COMPILER="$FPCSRC/compiler/ppcrossa64"
fi
[ -x "$COMPILER" ] || { echo "компилятор не собрался: $COMPILER"; exit 1; }

SYSROOT="$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
PKG=$(find "$FPCSRC/packages" -type d -name "$CPU-android" | sed 's/^/-Fu/' | tr '\n' ' ')

# BearLibTerminal собирается здесь же, и это не прихоть: игра ссылается на неё
# при компоновке, а Gradle собирал бы её только на следующем шаге — замкнутый
# круг. Заодно исчезает вторая сборка той же библиотеки: приложение подключает
# готовую.
echo "== BearLibTerminal под $ABI =="
mkdir -p "$OUT" "build/android"
cmake -S third_party/bearlibterminal -B "build/android/cmake-$ABI" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_BUILD_TYPE=Release > "build/android/cmake-$ABI.log" 2>&1
cmake --build "build/android/cmake-$ABI" --target BearLibTerminal -j"$(nproc)" >> "build/android/cmake-$ABI.log" 2>&1
BLT_SO="$(find third_party/bearlibterminal/Output -name 'libBearLibTerminal.so' | head -1)"
[ -n "$BLT_SO" ] || { echo "BearLibTerminal не собрался:"; tail -20 "build/android/cmake-$ABI.log"; exit 1; }
cp "$BLT_SO" "$OUT/"
echo "  $(file "$OUT/libBearLibTerminal.so" | cut -c1-90)"

echo "== библиотека игры =="
mkdir -p "$OUT" "build/android/units-$ABI"
PATH="$NDKBIN:$PATH" "$COMPILER" -Tandroid -P"$CPU" -Mobjfpc -Sh -O2 -dUSE_BLT \
    -Fu"$RTL" $PKG \
    -Fusrc/dungeon \
    -Futhird_party/bearlibterminal/Terminal/Include/Pascal \
    -FU"build/android/units-$ABI" \
    -Fl"$SYSROOT/usr/lib/$LIBDIR/$API" \
    -Fl"$SYSROOT/usr/lib/$LIBDIR" \
    -Fl"$OUT" \
    -FD"$NDKBIN" \
    -o"$OUT/libwwandroid.so" \
    src/android/wwandroid.pas

file "$OUT/libwwandroid.so"
echo "готово: $OUT/libwwandroid.so"
