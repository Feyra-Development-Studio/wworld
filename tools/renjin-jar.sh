#!/usr/bin/env bash
#
# Выдаёт путь к jar движка Renjin. Единственное место, где этот jar берётся:
# им пользуются и сверка движков, и сборка приложения под Android, и незачем
# им расходиться.
#
#   JAR=$(tools/renjin-jar.sh build/renjin)
#
# Порядок такой:
#
#   1. WWORLD_RENJIN_JAR — если задан, берётся он и больше ничего не делается;
#   2. подмодуль third_party/renjin — собирается из исходников;
#   3. nexus — скачивается опубликованный.
#
# Из исходников важно уметь не ради принципа. Опубликованный jar нельзя
# положить в приложение под Android: внутри него повторяются классы
# gcc-bridge и BLAS, а d8 на повторяющемся классе отказывается работать
# вовсе. В форке это исправлено (duplicatesStrategy у jarWithDependencies),
# и собранный отсюда jar переводится в dex без единого замечания.
#
# Сборке нужен JDK 8: Renjin собирается Gradle 6.6, который новее восьмой
# версии не понимает. Наши собственные классы при этом собираются JDK 17 —
# это разные вещи и мешать их не надо.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORK="${1:-build/renjin}"
NEXUS="https://nexus.bedatadriven.com/content/groups/public"
ART="org/renjin/renjin-script-engine"

mkdir -p "$WORK"

# 1. Готовый jar задан снаружи
if [ -n "${WWORLD_RENJIN_JAR:-}" ]; then
    [ -f "$WWORLD_RENJIN_JAR" ] || { echo "WWORLD_RENJIN_JAR указывает в никуда: $WWORLD_RENJIN_JAR" >&2; exit 1; }
    echo "движок задан снаружи: $WWORLD_RENJIN_JAR" >&2
    echo "$WWORLD_RENJIN_JAR"
    exit 0
fi

# 2. Сборка из подмодуля
if [ -f third_party/renjin/settings.gradle ]; then
    OUT="$WORK/renjin-from-source.jar"

    # Пересобирать каждый раз незачем: сборка занимает около минуты, а меняется
    # форк редко. Сверяемся по коммиту подмодуля.
    HAVE="$(cat "$WORK/.renjin-commit" 2>/dev/null || true)"
    WANT="$(git -C third_party/renjin rev-parse HEAD)"

    if [ -f "$OUT" ] && [ "$HAVE" = "$WANT" ]; then
        echo "движок собран ранее из $WANT" >&2
    else
        # JDK 8 ищем там, где он обычно лежит на бегунках GitHub, иначе
        # полагаемся на текущий JAVA_HOME и говорим, если он не тот.
        JDK8="${JAVA_HOME_8_X64:-${WWORLD_JDK8:-}}"
        if [ -z "$JDK8" ] && [ -x "${JAVA_HOME:-}/bin/javac" ]; then
            case "$("$JAVA_HOME/bin/javac" -version 2>&1)" in
                *" 1.8."*|*" 8."*) JDK8="$JAVA_HOME" ;;
            esac
        fi
        if [ -z "$JDK8" ]; then
            echo "для сборки Renjin нужен JDK 8 (Gradle 6.6 новее не понимает)." >&2
            echo "укажите его в WWORLD_JDK8 или задайте готовый jar в WWORLD_RENJIN_JAR." >&2
            exit 1
        fi

        echo "собираю движок из third_party/renjin ($WANT), JDK 8: $JDK8" >&2
        ( cd third_party/renjin && JAVA_HOME="$JDK8" ./gradlew --no-daemon -q \
              -Dfile.encoding=UTF-8 :script-engine:jarWithDependencies ) >&2

        SRC="$(find third_party/renjin/script-engine/build/libs \
               -name '*jar-with-dependencies*.jar' | head -1)"
        [ -n "$SRC" ] || { echo "сборка прошла, а jar не найден" >&2; exit 1; }
        cp "$SRC" "$OUT"
        echo "$WANT" > "$WORK/.renjin-commit"
    fi

    echo "$OUT"
    exit 0
fi

# 3. Опубликованный
echo "подмодуля third_party/renjin нет (tools/deps.sh android), беру опубликованный" >&2
curl -fsS "$NEXUS/$ART/maven-metadata.xml" -o "$WORK/metadata.xml"
VERSION="$(grep -oE '<release>[^<]+' "$WORK/metadata.xml" | head -1 | cut -d'>' -f2 || true)"
[ -n "$VERSION" ] || VERSION="$(grep -oE '<version>[^<]+' "$WORK/metadata.xml" | tail -1 | cut -d'>' -f2)"

JAR="$WORK/renjin-script-engine-$VERSION-jar-with-dependencies.jar"
[ -f "$JAR" ] || curl -fsS \
    "$NEXUS/$ART/$VERSION/renjin-script-engine-$VERSION-jar-with-dependencies.jar" -o "$JAR"
echo "$JAR"
