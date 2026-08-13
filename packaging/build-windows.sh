#!/usr/bin/env bash
# Кросс-сборка под Windows x64 с Linux и упаковка в zip.
#   packaging/build-windows.sh <версия> [каталог назначения]
# Требует: fpc с целью Win64 (пакеты fp-units-win-base, fp-units-win-fcl)
# и binutils-mingw-w64-x86-64 для линковки.
set -euo pipefail

VERSION="${1:?нужна версия, например 0.1.0}"
DIST="${2:-dist}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

rm -rf build/windows
mkdir -p build/windows/units build/windows/wworld "$DIST"

echo "== сборка exe =="
fpc -Twin64 -Mobjfpc -Sh -O2 -Fusrc/dungeon -FUbuild/windows/units \
    -obuild/windows/wworld/wworld.exe src/demo/demo.pas > /dev/null
fpc -Twin64 -Mobjfpc -Sh -O2 -Fusrc/dungeon -FUbuild/windows/units \
    -obuild/windows/wworld/wworld-walk.exe src/demo/wwwalk.pas > /dev/null

# скрипты кладём рядом с exe: программа ищет geometry.R в своём каталоге
cp scripts/geometry.R scripts/validate_dungeon.R README.md build/windows/wworld/
cat > build/windows/wworld/ЧИТАЙ.txt <<'EOF'
wworld — генератор подземелий

Нужен R: поставьте его с https://cran.r-project.org/bin/windows/base/
и убедитесь, что Rscript.exe виден в PATH.

  wworld.exe --seed 20260813 --levels 10 --out out --test
  wworld-walk.exe --json out\dungeon.json

Геометрию и топологию карты считает scripts/geometry.R, лежащий рядом с exe.
EOF

echo "== zip =="
( cd build/windows && zip -qr "$ROOT/$DIST/wworld_${VERSION}_win64.zip" wworld )
ls -1sh "$DIST"/wworld_*_win64.zip
