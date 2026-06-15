#!/bin/bash

SCRIPT_REPO="https://github.com/OpenVisualCloud/SVT-JPEG-XS.git"
SCRIPT_COMMIT="8e50180ad909a0bdcdf91b462c64033f0fe3e112"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Вырезаем флаг -flto, который ломает классический линкер
    sed -i 's/check_both_flags_add(-flto)//g' CMakeLists.txt || true

    if [[ "${PREFER_SHARED}" != "1" ]]; then
         # Удаляем принудительное скрытие символов на уровне всего проекта CMake
         sed -i 's/set(CMAKE_C_VISIBILITY_PRESET hidden)//g' CMakeLists.txt || true
         # Удаляем точечное скрытие символов для библиотеки SvtJpegxsLib
         sed -i 's/set_target_properties(SvtJpegxsLib PROPERTIES C_VISIBILITY_PRESET hidden)//g' Source/Lib/CMakeLists.txt || true
    fi

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
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"

        if ! grep -q -- "-lstdc++" "$PC_FILE"; then
            sed -i '/^Libs.private:/ s/$/ -lstdc++/' "$PC_FILE"
        fi
        sed -i 's|^Cflags:.*|Cflags: -I${includedir} -I${includedir}/svt-jpegxs -UDEF_DLL|' "$PC_FILE"
    done
}

ffbuild_configure() {
    echo --enable-libsvtjpegxs
}

ffbuild_unconfigure() {
    echo --disable-libsvtjpegxs
}