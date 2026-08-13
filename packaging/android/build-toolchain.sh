#!/usr/bin/env bash
# Кросс-компилятор Free Pascal под aarch64-android.
#
# Готового пакета не существует ни в Debian, ни в Ubuntu, поэтому компилятор
# собирается из исходников против NDK. Три места, где всё спотыкается, и как
# они обходятся:
#
# 1. Исходники из пакета fpc-source урезаны: в них нет makefile.cpu, без
#    которого сборка не идёт. Берём нетронутые с зеркала FPC.
# 2. FPC зовёт ассемблер по имени <префикс>as и передаёт ключи в стиле GNU as.
#    В NDK ассемблирует clang, поэтому подкладываем обёртку, переводящую
#    --defsym X=Y в -Wa,-defsym,X=Y (с одним дефисом — двойной clang не берёт)
#    и помечающую вход как ассемблерный: расширение .as clang не узнаёт.
# 3. FPC 3.2.2 порождает скрипт линковки, который lld отвергает
#    («unable to insert .data after .data1»), а GNU ld из NDK начиная с r23
#    убран. Берём aarch64-linux-gnu-ld из binutils — формат тот же.
set -euo pipefail

NDK_VERSION="${NDK_VERSION:-r26d}"
API="${API:-21}"
PREFIX="${PREFIX:-/opt}"
NDK="$PREFIX/android-ndk-$NDK_VERSION"
NDKBIN="$PREFIX/ndkbin"
FPCSRC="$PREFIX/fpc-src"

echo "== NDK =="
if [ ! -d "$NDK" ]; then
  curl -sL "https://dl.google.com/android/repository/android-ndk-$NDK_VERSION-linux.zip" -o /tmp/ndk.zip
  unzip -q /tmp/ndk.zip -d "$PREFIX"
fi
TOOLS="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"

echo "== обёртки инструментов =="
mkdir -p "$NDKBIN"
ln -sf "$TOOLS/llvm-ar" "$NDKBIN/aarch64-linux-android-ar"
ln -sf "$TOOLS/llvm-strip" "$NDKBIN/aarch64-linux-android-strip"
ln -sf "$(command -v aarch64-linux-gnu-ld)" "$NDKBIN/aarch64-linux-android-ld"
cat > "$NDKBIN/aarch64-linux-android-as" <<EOF
#!/bin/sh
CLANG=$TOOLS/aarch64-linux-android$API-clang
args=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --defsym) args="\$args -Wa,-defsym,\$2"; shift 2 ;;
    *) args="\$args \$1"; shift ;;
  esac
done
exec \$CLANG -x assembler -c \$args
EOF
chmod +x "$NDKBIN/aarch64-linux-android-as"

echo "== исходники FPC =="
[ -d "$FPCSRC" ] || git clone -q --depth 1 --branch release_3_2_2 \
  https://github.com/fpc/FPCSource.git "$FPCSRC"

echo "== сборка кросс-компилятора =="
cd "$FPCSRC"
PATH="$NDKBIN:$PATH" make -s crossall \
  CPU_TARGET=aarch64 OS_TARGET=android \
  CROSSBINDIR="$NDKBIN" BINUTILSPREFIX=aarch64-linux-android- \
  FPC="$(command -v ppcx64)"

echo "готово: $FPCSRC/compiler/ppcrossa64"
