cmake_minimum_required(VERSION 3.22.1)
project(wworld-android)

# Библиотека собирается из подмодуля, а не берётся готовым файлом: правки в
# форке должны доезжать до приложения сразу, без ручного переноса.
set(BLT_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/bearlibterminal)

if(NOT EXISTS ${BLT_ROOT}/CMakeLists.txt)
    message(FATAL_ERROR
        "Подмодуль BearLibTerminal не подтянут. Выполните: tools/deps.sh android")
endif()

add_subdirectory(${BLT_ROOT} ${CMAKE_CURRENT_BINARY_DIR}/bearlibterminal)

add_library(wworld SHARED glue.cpp)

target_include_directories(wworld PRIVATE ${BLT_ROOT}/Terminal/Include/C)
target_link_libraries(wworld BearLibTerminal android log)
