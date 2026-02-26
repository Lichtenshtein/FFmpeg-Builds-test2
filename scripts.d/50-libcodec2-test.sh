#!/bin/bash

# SCRIPT_REPO="https://github.com/arancormonk/codec2.git"
# SCRIPT_COMMIT="6a787012632b8941aa24a4ea781440b61de40f57"

# SCRIPT_REPO1="https://github.com/rhythmcache/codec2.git"
# SCRIPT_COMMIT1="6e0a0e09c065aa5401eb9c30d724240fffe890f1"

# SCRIPT_REPO2="https://github.com/zups/codec2.git"
# SCRIPT_COMMIT2="371c82ae557f1b033cf4b625be435bb4b88ef70b"

# SCRIPT_REPO3="https://github.com/Alex-Pennington/codec2.git"
# SCRIPT_COMMIT3="19571e0a2b42340597fd762803f6eb9d030ee4c5"

SCRIPT_REPO4="https://github.com/drowe67/codec2.git"
SCRIPT_COMMIT4="96e8a19c2487fd83bd981ce570f257aef42618f9"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    # if [[ -d "/builder/patches/libcodec2-test" ]]; then
        # for patch in "/builder/patches/libcodec2-test"/*.patch; do
            # log_info "APPLYING PATCH: $patch"
            # if patch -p1 -N -r - < "$patch"; then
                # log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            # else
                # log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
            # fi
        # done
    # fi

    # Сначала полностью вырезаем проблемный блок ExternalProject
    # Мы заменяем его на пустышку, чтобы CMake не ругался на отсутствие цели generate_codebook
    sed -i '/if(CMAKE_CROSSCOMPILING)/,/endif(CMAKE_CROSSCOMPILING)/c\add_executable(generate_codebook IMPORTED)\nset_target_properties(generate_codebook PROPERTIES IMPORTED_LOCATION /usr/bin/true)' src/CMakeLists.txt

    mkdir build && cd build

    # В репозитории codec2 файлы кодовых книг лежат в папке 'src'.
    # Мы создадим в папке build симлинки на них, чтобы CMake их увидел как "сгенерированные"
    for f in ../src/codebook*.c; do
        ln -sf "$f" "$(basename "$f")"
    done

    local mycmake=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_C_FLAGS="$CFLAGS"
        -DCMAKE_CXX_FLAGS="$CXXFLAGS"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
        -DBUILD_SHARED_LIBS=OFF
        # -DGENERATE_CODEBOOKS=OFF
        # -DGENERATE_CODEBOOK="$(pwd)/../fake_gen"
        -DGENERATE_CODEBOOK=/usr/bin/true
        -DUNITTEST=OFF
        -DINSTALL_EXAMPLES=OFF
        # Дополнительные флаги для кросс-компиляции
        -DBUILD_TESTING=OFF
    )

    cmake "${mycmake[@]}" ..

    # Сборка только библиотеки. 
    # Если 'make codec2' все еще капризничает из-за отсутствия исходников,
    # мы скомпилируем их вручную и добавим в архив.
    if ! make -j$(nproc) codec2 $MAKE_V; then
        log_warn "Standard make failed, performing manual object compilation..."
        # Компилируем все .c файлы из папки src
        for f in ../src/*.c; do
            [[ "$f" == *"generate_codebook.c"* ]] && continue
            ${CC} ${CFLAGS} -I../src -I. -c "$f" -o "$(basename "${f%.c}.obj")"
        done
        ${AR} rcs src/libcodec2.a *.obj
    fi

    # Установка
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/codec2"
    
    # Проверяем, где в итоге оказался файл
    if [[ -f "src/libcodec2.a" ]]; then
        cp src/libcodec2.a "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
    elif [[ -f "libcodec2.a" ]]; then
        cp libcodec2.a "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
    fi

    cp ../src/codec2.h "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/codec2/"
    
    # Генерируем pkg-config
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/codec2.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: codec2
Description: Next generation digital radio voice codec
Version: 1.2.0
Libs: -L\${libdir} -lcodec2
Cflags: -I\${includedir}/codec2
EOF

    # Проверка финального наличия
    if [[ -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libcodec2.a" ]]; then
        log_info "SUCCESS: libcodec2.a is ready."
    else
        log_error "CRITICAL: libcodec2.a still missing!"
        exit 1
    fi

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
