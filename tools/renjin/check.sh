#!/usr/bin/env bash
# Сверка GNU R и Renjin как двух взаимозаменяемых движков геометрии.
#
# Оба запускаются одинаково — дочерним процессом, читающим stdin. Сначала
# сверяются ответы на наборе команд, затем генерируются десять этажей каждым
# движком и сравниваются целиком: совпадение ответов ещё не значит совпадения
# карт при одном seed.
#
#   tools/renjin/check.sh [каталог сборки] [бинарник demo] [seed]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
WORK="${1:-build/renjin}"
DEMO="${2:-./src/demo/demo}"
SEED="${3:-20260813}"
NEXUS="https://nexus.bedatadriven.com/content/groups/public"
ART="org/renjin/renjin-script-engine"

mkdir -p "$WORK"

echo "== версия Renjin =="
curl -fsS "$NEXUS/$ART/maven-metadata.xml" -o "$WORK/metadata.xml"
VERSION="$(grep -oE '<release>[^<]+' "$WORK/metadata.xml" | head -1 | cut -d'>' -f2 || true)"
[ -n "$VERSION" ] || VERSION="$(grep -oE '<version>[^<]+' "$WORK/metadata.xml" | tail -1 | cut -d'>' -f2)"
echo "$VERSION"

JAR="$WORK/renjin-script-engine-$VERSION-jar-with-dependencies.jar"
[ -f "$JAR" ] || curl -fsS "$NEXUS/$ART/$VERSION/renjin-script-engine-$VERSION-jar-with-dependencies.jar" -o "$JAR"
ls -sh "$JAR"

echo "== сборка движка =="
mkdir -p "$WORK/classes"
javac -cp "$JAR" -d "$WORK/classes" tools/renjin/RenjinHost.java

ENGINE="java -cp $JAR:$WORK/classes RenjinHost"

echo "== сверка ответов на наборе команд =="
Rscript scripts/geometry.R < tools/renjin/commands.txt > "$WORK/gnu-r.txt"
$ENGINE scripts/geometry.R < tools/renjin/commands.txt > "$WORK/renjin.txt" 2> "$WORK/renjin.err" || true
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
if diff -r "$WORK/out-gnu" "$WORK/out-renjin" > "$WORK/maps.diff" 2>&1; then
  echo "СОВПАДАЕТ: подземелья при seed $SEED побайтово одинаковы на обоих движках"
  exit 0
fi
echo "РАСХОЖДЕНИЕ в картах:"
head -30 "$WORK/maps.diff"
exit 1
