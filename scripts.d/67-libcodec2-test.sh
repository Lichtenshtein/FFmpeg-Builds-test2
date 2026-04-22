#!/bin/bash

# SCRIPT_REPO="https://github.com/arancormonk/codec2.git"
# SCRIPT_COMMIT="6a787012632b8941aa24a4ea781440b61de40f57"

# SCRIPT_REPO1="https://github.com/rhythmcache/codec2.git"
# SCRIPT_COMMIT1="6e0a0e09c065aa5401eb9c30d724240fffe890f1"

# SCRIPT_REPO2="https://github.com/zups/codec2.git"
# SCRIPT_COMMIT2="371c82ae557f1b033cf4b625be435bb4b88ef70b"

SCRIPT_REPO3="https://github.com/Alex-Pennington/codec2.git"
SCRIPT_COMMIT3="19571e0a2b42340597fd762803f6eb9d030ee4c5"

# SCRIPT_REPO4="https://github.com/drowe67/codec2.git"
# SCRIPT_COMMIT4="96e8a19c2487fd83bd981ce570f257aef42618f9"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # 1Полностью отключаем попытки генерации кодовых книг
    # Мы заменяем вызов add_custom_command на пустышку, чтобы CMake использовал существующие файлы
    sed -i 's/add_custom_command/COMMAND ${CMAKE_COMMAND} -E true #/g' src/CMakeLists.txt
    
    mkdir -p build && cd build

    if [ -f "CMakeLists.txt" ]; then
        sed -i 's/add_subdirectory(demo)/#add_subdirectory(demo)/g' CMakeLists.txt
        sed -i 's/add_subdirectory(unittest)/#add_subdirectory(unittest)/g' CMakeLists.txt
    fi

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DGENERATE_CODEBOOK=/usr/bin/true
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DUNITTEST=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    # Сборка только библиотеки. 
    ninja $NINJA_V codec2 || return 1

    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1


    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/codec2"
    
    # Проверяем, где в итоге оказался файл
    if [[ -f "src/libcodec2.a" ]]; then
        cp src/libcodec2.a "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
    elif [[ -f "libcodec2.a" ]]; then
        cp libcodec2.a "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
    fi

    cp ../src/codec2.h "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/codec2/"
    
    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/codec2.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: codec2
Description: Next generation digital radio voice codec
Version: 1.2.0
Libs: -L\${libdir} -lcodec2
Libs.private: -lm
Cflags: -I\${includedir}
EOF

    # Проверка финального наличия
    if [[ -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libcodec2.a" ]]; then
        log_info "${CHECK_MARK} SUCCESS: libcodec2.a is ready."
    else
        log_error "libcodec2.a still missing!"
        return 1
    fi
}

ffbuild_configure() {
    echo --enable-libcodec2
}

ffbuild_unconfigure() {
    echo --disable-libcodec2
}
