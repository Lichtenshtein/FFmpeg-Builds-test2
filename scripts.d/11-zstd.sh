#!/bin/bash

SCRIPT_REPO="https://github.com/facebook/zstd.git"
SCRIPT_COMMIT="1168da0e567960d50cba1b58c9b0ba047ece4733"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Исправляем CMakeLists.txt ПЕРЕД запуском, чтобы избежать ошибки CXX
    # Добавляем CXX в список языков проекта
    sed -i '/LANGUAGES C/s/C/C CXX/' build/cmake/CMakeLists.txt

    # zstd требует запуска CMake из поддиректории build/cmake
    cd build/cmake
    rm -rf builddir && mkdir builddir && cd builddir

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DZSTD_BUILD_STATIC=ON
        -DZSTD_BUILD_SHARED=OFF
        -DZSTD_BUILD_PROGRAMS=OFF
        -DZSTD_BUILD_TESTS=OFF
        -DZSTD_BUILD_CONTRIB=OFF
        -DCMAKE_CXX_COMPILER="$CXX"
        -DZSTD_MULTITHREAD_SUPPORT=ON
        -DZSTD_LEGACY_SUPPORT=ON
    )

    if [[ "$USE_LTO" == "1" ]]; then
        myconf+=( -DZSTD_USE_LTO=ON )
    fi

    # Добавляем -DCMAKE_CXX_COMPILER, чтобы CMake инициализировал CXX
    # и не падал на проверке флагов AddZstdCompilationFlags
    # Принудительно передаем CXX компилятор
    cmake "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS $CPPFLAGS -DZSTD_MULTITHREAD -DZSTD_STATIC_LINKING" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS $CPPFLAGS -DZSTD_MULTITHREAD -DZSTD_STATIC_LINKING" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_CXX_COMPILER="$CXX" \
        .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/libzstd.pc"
    if [[ -f "$PC_FILE" ]]; then
        if ! grep -q "\-lpthread" "$PC_FILE"; then
            sed -i 's/Libs.private:/& -lpthread /' "$PC_FILE"
        fi
        if ! grep -q "\-DZSTD_MULTITHREAD" "$PC_FILE"; then
            sed -i '/^Cflags:/ s/$/ -DZSTD_MULTITHREAD -DZSTD_STATIC_LINKING/' "$PC_FILE"
        fi
    fi

}

ffbuild_cppflags() {
    echo "-DZSTD_STATIC_LINKING -DZSTD_MULTITHREAD"
}

ffbuild_configure() {
    echo --enable-zstd
}

ffbuild_unconfigure() {
    echo --disable-zstd
}
