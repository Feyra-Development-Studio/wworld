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

# Игра собирается не здесь: её собирает Free Pascal кросс-компилятором
# (packaging/android/build-library.sh), а CMake только подключает готовое.
# Свести это в одну сборку нельзя — CMake не умеет Pascal, а FPC не умеет
# проект Gradle.
set(WWANDROID ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../build/android/${ANDROID_ABI}/libwwandroid.so)

if(EXISTS ${WWANDROID})
    add_library(wwandroid SHARED IMPORTED)
    set_target_properties(wwandroid PROPERTIES IMPORTED_LOCATION ${WWANDROID})
    target_link_libraries(wworld wwandroid)
    message(STATUS "игра подключена: ${WWANDROID}")
else()
    # Собираться без игры приложение обязано: связка проверяется отдельно, и
    # молчаливое включение пустышки было бы хуже внятного отказа при запуске.
    message(WARNING "библиотеки игры нет (${WWANDROID}); "
                    "соберите packaging/android/build-library.sh ${ANDROID_ABI}")
endif()

target_include_directories(wworld PRIVATE ${BLT_ROOT}/Terminal/Include/C)
target_link_libraries(wworld BearLibTerminal android log)
