#!/usr/bin/env bash
#
# Проверка синтаксиса связки с Android без NDK.
#
#   tools/check-glue.sh
#
# NDK в песочницу не влезает, и каждая опечатка в glue.cpp до сих пор стоила
# круга по CI: сборка APK занимает минуты, а ловила она забытую скобку. Здесь
# заглушки заголовков Android дают обычному g++ разобрать тот же файл за
# секунду.
#
# Это проверка синтаксиса, а не сборки: заглушки ничего не делают, и
# работоспособность по ним судить нельзя. Но опечатки ловятся все.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BLT="third_party/bearlibterminal/Terminal/Include/C"
[ -f "$BLT/BearLibTerminal.h" ] || { echo "нет подмодуля: tools/deps.sh android"; exit 2; }

g++ -fsyntax-only -std=c++17 -D__ANDROID__ \
    -Itools/android-stubs -I"$BLT" \
    android/app/src/main/cpp/glue.cpp

echo "связка разбирается"
