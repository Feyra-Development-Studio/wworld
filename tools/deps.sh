#!/usr/bin/env bash
#
# Подтягивает только те подмодули, которые нужны конкретной сборке.
#
# Раньше все задания забирали подмодули через submodules: recursive, то есть
# каждое качало всё. Пока подмодуль был один и весил четыре килобайта, это
# ничего не стоило. С появлением Renjin (57 МБ) это стало заметно, а главное —
# бессмысленно: сборке под Linux интерпретатор на JVM не нужен вовсе, а сборке
# под Android не нужен BearLibTerminal.
#
# Набор зависит от того, ЧТО собираем, а не от того, ГДЕ собираем: движок
# геометрии у нас разный для разных поставок (#4, #5, #6). На Linux это
# Rscript, на Android — Renjin внутри приложения, а на Windows выбор делает
# установщик по режиму установки, и ветки gnu и renjin существуют затем, чтобы
# этот выбор был обоснован замером, а не вкусом. Поэтому пресеты названы по
# поставке, а не по системе.
#
#   tools/deps.sh core             ходилка и генератор на Linux: BearLibTerminal
#   tools/deps.sh android          приложение на Renjin: renjin
#   tools/deps.sh engine-check     сверка движков: renjin
#   tools/deps.sh windows-gnu      ветка gnu: BearLibTerminal, R ставит установщик
#   tools/deps.sh windows-renjin   ветка renjin: BearLibTerminal и renjin
#   tools/deps.sh all              всё сразу
#
# Можно назвать подмодули и поимённо:
#
#   tools/deps.sh -- bearlibterminal renjin
#
set -euo pipefail

usage() {
    sed -n '3,27p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

resolve() {
    case "$1" in
        core|linux)      echo "bearlibterminal" ;;
        android)         echo "renjin" ;;
        engine-check)    echo "renjin" ;;
        windows-gnu)     echo "bearlibterminal" ;;
        windows-renjin)  echo "bearlibterminal renjin" ;;
        all)             echo "bearlibterminal renjin" ;;
        none)            echo "" ;;
        *)
            echo "неизвестная поставка: $1" >&2
            echo "известны: core, android, engine-check, windows-gnu, windows-renjin, all, none" >&2
            exit 2
            ;;
    esac
}

fetch() {
    local name="$1" path="third_party/$1"

    if ! git config --file .gitmodules --get "submodule.$path.path" > /dev/null 2>&1; then
        echo "нет такого подмодуля: $path" >&2
        exit 2
    fi

    # Сначала мелкой копией: истории третьей стороны нам не нужны.
    # Но закреплённый коммит может оказаться глубже верхушки ветки — тогда
    # мелкая копия его не увидит, и приходится забирать целиком. Молча
    # проглатывать такое нельзя: это ровно тот случай, когда сборка «почти
    # работает», а потом падает на несовпадении версии.
    if git submodule update --init --depth 1 --recursive -- "$path" 2>/dev/null; then
        echo "  $name: взят мелкой копией"
    else
        echo "  $name: мелкой копией не вышло (закреплённый коммит глубже верхушки), беру целиком"
        git submodule update --init --recursive -- "$path"
    fi
}

main() {
    local wanted=()

    case "${1:-}" in
        ""|-h|--help) usage 0 ;;
        --)           shift; wanted=("$@") ;;
        *)            read -r -a wanted <<< "$(resolve "$1")" ;;
    esac

    cd "$(dirname "$0")/.."

    if [ "${#wanted[@]}" -eq 0 ]; then
        echo "подмодули не нужны"
        return 0
    fi

    echo "подмодули: ${wanted[*]}"
    for name in "${wanted[@]}"; do
        fetch "$name"
    done
}

main "$@"
