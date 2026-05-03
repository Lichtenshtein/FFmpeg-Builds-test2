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
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DZSTD_BUILD_PROGRAMS=OFF
        -DZSTD_BUILD_TESTS=OFF
        -DZSTD_BUILD_CONTRIB=OFF
        -DCMAKE_CXX_COMPILER="$CXX"
        -DZSTD_MULTITHREAD_SUPPORT=ON
        -DZSTD_LEGACY_SUPPORT=ON
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DZSTD_STATIC_LINKING"
    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DZSTD_BUILD_STATIC=OFF -DZSTD_BUILD_SHARED=ON ) || \
        myconf+=( -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_SHARED=OFF )

    # Добавляем -DCMAKE_CXX_COMPILER, чтобы CMake инициализировал CXX
    # и не падал на проверке флагов AddZstdCompilationFlags
    # Принудительно передаем CXX компилятор
    cmake -G Ninja "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS $CPPFLAGS -DZSTD_MULTITHREAD $static_flags" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS $CPPFLAGS -DZSTD_MULTITHREAD $static_flags" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_CXX_COMPILER="$CXX" \
        .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/libzstd.pc"
    if [[ -f "$PC_FILE" ]]; then
        if ! grep -q "\-lpthread" "$PC_FILE"; then
            sed -i 's/Libs.private:/& -pthread /' "$PC_FILE"
        fi
        if ! grep -q "\-DZSTD_MULTITHREAD" "$PC_FILE"; then
            sed -i "/^Cflags:/ s/$/ -DZSTD_MULTITHREAD/" "$PC_FILE"
        fi
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
    fi

    ln -sf libzstd.pc "$PC_DIR/zstd.pc"
}

# no such flags :\

# ffbuild_cppflags() {
    # echo "$static_flags -DZSTD_MULTITHREAD"
# }

# ffbuild_configure() {
    # echo --enable-zstd
# }

# ffbuild_unconfigure() {
    # echo --disable-zstd
# }
