#!/usr/bin/env bash
# Спайк #2: сверка ответов geometry.R под GNU R и под Renjin.
#
# Renjin публикуется не на Maven Central, а в nexus.bedatadriven.com, поэтому
# jar тянется оттуда, а версия берётся из maven-metadata.xml, чтобы скрипт не
# устаревал вместе с зашитым номером.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
WORK="${1:-build/renjin}"
NEXUS="https://nexus.bedatadriven.com/content/groups/public"
ART="org/renjin/renjin-script-engine"

mkdir -p "$WORK"

echo "== определяю версию Renjin =="
curl -fsS "$NEXUS/$ART/maven-metadata.xml" -o "$WORK/metadata.xml"
VERSION="$(grep -oE '<release>[^<]+' "$WORK/metadata.xml" | head -1 | cut -d'>' -f2 || true)"
if [ -z "$VERSION" ]; then
  VERSION="$(grep -oE '<version>[^<]+' "$WORK/metadata.xml" | tail -1 | cut -d'>' -f2)"
fi
echo "версия: $VERSION"

JAR="$WORK/renjin-script-engine-$VERSION-jar-with-dependencies.jar"
if [ ! -f "$JAR" ]; then
  echo "== качаю jar =="
  curl -fsS "$NEXUS/$ART/$VERSION/renjin-script-engine-$VERSION-jar-with-dependencies.jar" -o "$JAR"
fi
ls -sh "$JAR"

echo "== эталон GNU R =="
Rscript tools/renjin-spike/reference.R scripts/geometry.R tools/renjin-spike/commands.txt \
  > "$WORK/gnu-r.txt"

echo "== прогон под Renjin =="
set +e
java -cp "$JAR" tools/renjin-spike/RenjinSpike.java \
  scripts/geometry.R tools/renjin-spike/commands.txt > "$WORK/renjin.txt" 2> "$WORK/renjin.err"
RC=$?
set -e
if [ $RC -ne 0 ]; then
  echo "прогон под Renjin завершился с кодом $RC:"
  head -30 "$WORK/renjin.err"
fi

echo "== сверка =="
paste -d'|' <(nl -ba tools/renjin-spike/commands.txt | sed 's/^ *//') /dev/null > /dev/null 2>&1 || true
if diff -q "$WORK/gnu-r.txt" "$WORK/renjin.txt" > /dev/null 2>&1; then
  echo "СОВПАДАЕТ: ответы Renjin побайтово равны GNU R"
  exit 0
fi

echo "РАСХОЖДЕНИЯ (слева GNU R, справа Renjin):"
paste -d'\n' \
  <(sed 's/^/  gnu    /' "$WORK/gnu-r.txt") \
  <(sed 's/^/  renjin /' "$WORK/renjin.txt") \
  | awk 'NR%2{g=$0; next} {if (substr(g,10)!=substr($0,10)) {print g; print $0; print ""}}' \
  | cut -c1-160
echo
echo "команд всего: $(grep -c . tools/renjin-spike/commands.txt)"
echo "строк у GNU R: $(wc -l < "$WORK/gnu-r.txt"), у Renjin: $(wc -l < "$WORK/renjin.txt")"
exit 1
