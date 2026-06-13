#!/bin/bash

SCRIPT_REPO="https://github.com/OpenVisualCloud/SVT-JPEG-XS.git"
SCRIPT_COMMIT="8e50180ad909a0bdcdf91b462c64033f0fe3e112"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Это принудительно отключит манглинг имен C++ на этапе сборки самой библиотеки!
    log_info "🔧 Patching SvtJpegxs API headers with extern \"C\" blocks for MinGW..."

    # Находим все заголовочные файлы API
    find . -type f -name "SvtJpegxs*.h" | while read -r header; do
        # Проверяем, нет ли там уже extern "C" (чтобы избежать дублирования при повторной сборке из кэша)
        if ! grep -q 'extern "C"' "$header"; then
            # Создаем временный файл
            local tmp_h=$(mktemp)

            # Записываем открывающий блок extern "C" в начало файла
            echo -e "#ifdef __cplusplus\nextern \"C\" {\n#endif\n" > "$tmp_h"
            # Копируем оригинальное содержимое заголовка
            cat "$header" >> "$tmp_h"
            # Записываем закрывающий блок в самый конец файла
            echo -e "\n#ifdef __cplusplus\n}\n#endif" >> "$tmp_h"

            # Заменяем оригинал исправленной версией
            mv "$tmp_h" "$header"
            log_debug "Successfully wrapped: $(basename "$header")"
        fi
    done

    # отключаем автоматическое определение архитектуры хоста
    # чтобы он не взял флаги процессора GitHub раннера
    sed -i 's/-march=native//g' CMakeLists.txt || true

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_TESTING=OFF
        -DBUILD_APPS=OFF
        -DENABLE_NATIVE=OFF
        -DENABLE_NASM=ON
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
    )

    # Специальные флаги для MinGW, чтобы избежать сегфолтов
    # -mstackrealign (выравнивание стека для cflags moved to base_cflags)
    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -fno-asynchronous-unwind-tables -mstackrealign" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -fno-asynchronous-unwind-tables -mstackrealign" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    for PC_FILE in "$PC_DIR"/SvtJpegxs*.pc; do
        [[ -f "$PC_FILE" ]] || continue
        # Исправляем префикс
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        if ! grep -q -- "-lstdc++" "$PC_FILE"; then
            sed -i '/^Libs.private:/ s/$/ -lstdc++/' "$PC_FILE"
        fi
    done

    ln -sf "$PC_DIR/SvtJpegxsEnc.pc" "$PC_DIR/svtjpegxs.pc"
}

ffbuild_configure() {
    echo --enable-libsvtjpegxs
}

ffbuild_unconfigure() {
    echo --disable-libsvtjpegxs
}