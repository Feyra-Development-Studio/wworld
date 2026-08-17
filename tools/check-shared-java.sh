#!/usr/bin/env bash
#
# Общий код на Java должен собираться и для настольной платформы, и для Android.
#
#   tools/check-shared-java.sh [путь к android.jar]
#
# Классы из java/src общие: ими пользуется и сверка движков на настольной
# сборке, и приложение под Android. А библиотеки под ними разные, и расходятся
# они молча — org.json с maven объявляет JSONException наследником
# RuntimeException, android.jar считает его проверяемым. Из-за этого один и тот
# же код собирался на одной платформе и не собирался на другой, и узнавалось
# это спустя восемь минут прогона.
#
# Здесь обе сборки проверяются за секунды.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORK="${WORK:-build/shared-java}"
ANDROID_JAR="${1:-${ANDROID_JAR:-}}"
mkdir -p "$WORK"

RENJIN="$(tools/renjin-jar.sh "$WORK/renjin" 2>/dev/null || true)"
[ -n "$RENJIN" ] || { echo "нет движка Renjin: tools/renjin-jar.sh"; exit 2; }

JSON="$WORK/json.jar"
[ -f "$JSON" ] || curl -fsS \
    "https://repo1.maven.org/maven2/org/json/json/20240303/json-20240303.jar" -o "$JSON"

echo "== настольная сборка =="
javac -encoding UTF-8 -cp "$RENJIN:$JSON" -d "$WORK/desktop" java/src/ru/wworld/*.java
echo "  собирается"

if [ -z "$ANDROID_JAR" ] || [ ! -f "$ANDROID_JAR" ]; then
    echo "== Android пропущен: не указан android.jar =="
    echo "   (это не успех, это непроверенная платформа)"
    exit 0
fi

echo "== сборка против android.jar =="
javac -encoding UTF-8 -cp "$RENJIN:$ANDROID_JAR" -d "$WORK/android" java/src/ru/wworld/*.java
echo "  собирается"
