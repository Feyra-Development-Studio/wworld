#!/usr/bin/env bash
# Сверка GNU R и Renjin как двух взаимозаменяемых движков геометрии.
#
# Оба запускаются одинаково — дочерним процессом, читающим stdin. Сначала
# сверяются ответы на наборе команд, затем генерируются десять этажей каждым
# движком и сравниваются целиком: совпадение ответов ещё не значит совпадения
# карт при одном seed.
#
#   tests/engine-check/check.sh [каталог сборки] [бинарник demo] [seed]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
WORK="${1:-build/renjin}"
DEMO="${2:-./src/demo/demo}"
SEED="${3:-20260813}"
mkdir -p "$WORK"

echo "== движок Renjin =="
# Откуда берётся jar, решает tools/renjin-jar.sh — одно место на все поставки.
JAR="$(tools/renjin-jar.sh "$WORK")"
ls -sh "$JAR"

echo "== библиотека org.json =="
# На Android org.json входит в саму систему, здесь нужна отдельная.
JSON="$WORK/json.jar"
[ -f "$JSON" ] || curl -fsS "https://repo1.maven.org/maven2/org/json/json/20240303/json-20240303.jar" -o "$JSON"

echo "== сборка Java-части =="
mkdir -p "$WORK/classes"
javac -encoding UTF-8 -cp "$JAR:$JSON" -d "$WORK/classes" java/src/ru/wworld/*.java

ENGINE="java -Dstdout.encoding=UTF-8 -cp $JAR:$JSON:$WORK/classes ru.wworld.RenjinHost"

echo "== сверка ответов на наборе команд =="
Rscript scripts/geometry.R < tests/engine-check/commands.txt > "$WORK/gnu-r.txt"
$ENGINE scripts/geometry.R < tests/engine-check/commands.txt > "$WORK/renjin.txt" 2> "$WORK/renjin.err" || true
if ! diff -u "$WORK/gnu-r.txt" "$WORK/renjin.txt" > "$WORK/answers.diff"; then
  echo "РАСХОЖДЕНИЕ в ответах:"
  head -40 "$WORK/answers.diff"
  echo "--- stderr Renjin ---"; head -20 "$WORK/renjin.err"
  exit 1
fi
echo "ответы совпадают построчно ($(grep -c . "$WORK/gnu-r.txt") команд)"

echo "== генерация десяти этажей каждым движком =="
rm -rf "$WORK/out-gnu" "$WORK/out-renjin"
"$DEMO" --seed "$SEED" --levels 10 --out "$WORK/out-gnu" --test > "$WORK/gen-gnu.log"
tail -2 "$WORK/gen-gnu.log"
"$DEMO" --seed "$SEED" --levels 10 --out "$WORK/out-renjin" --test --engine "$ENGINE" > "$WORK/gen-renjin.log"
tail -2 "$WORK/gen-renjin.log"

echo "== сверка карт =="
if ! diff -r "$WORK/out-gnu" "$WORK/out-renjin" > "$WORK/maps.diff" 2>&1; then
  echo "РАСХОЖДЕНИЕ в картах:"
  head -30 "$WORK/maps.diff"
  exit 1
fi
echo "подземелья при seed $SEED побайтово одинаковы на обоих движках"

# То же самое, но сборкой на Java: именно она поедет на Android, где
# генератора не будет, а в приложении окажется только граф.
echo "== сборка карты на Java из графа =="
java -Dstdout.encoding=UTF-8 -cp "$JAR:$JSON:$WORK/classes" ru.wworld.RebuildCheck \
     scripts/geometry.R "$WORK/out-gnu/dungeon.json" "$WORK/out-gnu/csv"

echo "ВСЁ СОВПАЛО"
exit 0
