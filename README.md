# Dungeon generator (wworld/tests)

Это начальный skeleton для модуля генерации подземелий.

Файлы:
- src/dungeon/dungeon_generator.pas - основные классы (заглушки)
- src/demo/demo.pas - простая программа для сборки и проверки
- scripts/generate_geometry.R - R-скрипт (rscript) для геометрии и векторных операций
- viewer/index.html - лёгкий HTML/JS viewer для просмотра geometry.json на телефоне
- .github/workflows/ci.yml - GitHub Actions: сборка и запуск тестов (fpc + rscript)

Интеграция:
- Pascal вызывает rscript (scripts/generate_geometry.R) для внутренней геометрии.
- JSON (geometry.json) — основной формат уровня; CSV экспорт будет добавлен в следующих коммитах.

