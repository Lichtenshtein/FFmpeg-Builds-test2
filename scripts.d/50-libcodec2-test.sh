#!/bin/bash

# SCRIPT_REPO="https://github.com/arancormonk/codec2.git"
# SCRIPT_COMMIT="6a787012632b8941aa24a4ea781440b61de40f57"

# SCRIPT_REPO2="https://github.com/rhythmcache/codec2.git"
# SCRIPT_COMMIT2="6e0a0e09c065aa5401eb9c30d724240fffe890f1"

# SCRIPT_REPO3="https://github.com/zups/codec2.git"
# SCRIPT_COMMIT3="371c82ae557f1b033cf4b625be435bb4b88ef70b"

SCRIPT_REPO="https://github.com/Alex-Pennington/codec2.git"
SCRIPT_COMMIT="19571e0a2b42340597fd762803f6eb9d030ee4c5"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/libcodec2-test" ]]; then
        for patch in "/builder/patches/libcodec2-test"/*.patch; do
            log_info "APPLYING PATCH: $patch"
            if patch -p1 -N -r - < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                # return 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    # Это предотвратит запуск и копирование generate_codebook
    # Раскомментировать если папка src/codec2_native всё еще вызывает ошибки линковки:
    # sed -i 's/add_subdirectory(codec2_native)//g' src/CMakeLists.txt
    # sed -i 's/add_dependencies(codec2 codec2_native)//g' src/CMakeLists.txt

    # Вместо удаления subdirectories, мы принудительно отключаем поиск 
    # инструментов, которые должны запускаться на хосте.
    # В этом форке CMakeLists может игнорировать -DGENERATE_CODEBOOKS=OFF в некоторых местах.

    # Исправляем CMakeLists, чтобы он не пытался собирать тесты и инструменты хоста
    sed -i 's/add_subdirectory(unittest)//g' CMakeLists.txt
    sed -i 's/add_subdirectory(demo)//g' CMakeLists.txt

    mkdir build && cd build

    local mycmake=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_C_FLAGS="$CFLAGS"
        -DCMAKE_CXX_FLAGS="$CXXFLAGS"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
        -DBUILD_SHARED_LIBS=OFF
        -DGENERATE_CODEBOOKS=OFF
        -DUNITTEST=OFF
        -DINSTALL_EXAMPLES=OFF
        # Дополнительные флаги для кросс-компиляции
        -DBUILD_TESTING=OFF
    )

    cmake "${mycmake[@]}" ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправление .pc файла (Codec2 иногда забывает про -lm)
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/codec2.pc"
    if [[ -f "$PC_FILE" ]]; then
        if ! grep -q "Libs.private" "$PC_FILE"; then
            echo "Libs.private: -lm" >> "$PC_FILE"
        fi
    fi
}

ffbuild_configure() {
    echo --enable-libcodec2
}

ffbuild_unconfigure() {
    echo --disable-libcodec2
}
