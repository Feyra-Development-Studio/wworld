cmake_minimum_required(VERSION 3.22.1)
project(wworld-android)

# Библиотека собирается из подмодуля, а не берётся готовым файлом: правки в
# форке должны доезжать до приложения сразу, без ручного переноса.
set(BLT_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/bearlibterminal)

if(NOT EXISTS ${BLT_ROOT}/CMakeLists.txt)
    message(FATAL_ERROR
        "Подмодуль BearLibTerminal не подтянут. Выполните: tools/deps.sh android")
endif()

# Обе готовые библиотеки собирает packaging/android/build-library.sh: игре
# нужна библиотека терминала при компоновке, а Gradle дошёл бы до неё только
# сейчас — замкнутый круг. Здесь они лишь подключаются.
set(PREBUILT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../build/android/${ANDROID_ABI})

foreach(LIB BearLibTerminal wwandroid)
    if(NOT EXISTS ${PREBUILT}/lib${LIB}.so)
        message(FATAL_ERROR
            "нет lib${LIB}.so для ${ANDROID_ABI}. "
            "Соберите: packaging/android/build-library.sh ${ANDROID_ABI}")
    endif()
    add_library(${LIB} SHARED IMPORTED)
    set_target_properties(${LIB} PROPERTIES IMPORTED_LOCATION ${PREBUILT}/lib${LIB}.so)
endforeach()

add_library(wworld SHARED glue.cpp)

target_include_directories(wworld PRIVATE ${BLT_ROOT}/Terminal/Include/C)
target_link_libraries(wworld BearLibTerminal wwandroid android log)
