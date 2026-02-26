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

    # Вырезаем ExternalProject и заменяем его на пустышку
    sed -i '/if(CMAKE_CROSSCOMPILING)/,/endif(CMAKE_CROSSCOMPILING)/c\add_executable(generate_codebook IMPORTED)\nset_target_properties(generate_codebook PROPERTIES IMPORTED_LOCATION /usr/bin/true)' src/CMakeLists.txt

    # Включаем все файлы кодовых книг в список исходников библиотеки.
    # По умолчанию CMake ждет их генерации в папку build, но мы возьмем их из src.
    # Мы добавляем их в переменную CODEC2_SRCS прямо в CMakeLists.txt
    sed -i '/set(CODEC2_SRCS/a \    codebook0.c\n    codebook1.c\n    codebook2.c\n    codebook3.c\n    codebook4.c\n    codebookd.c\n    codebookdt.c\n    codebookge.c\n    codebookjvm.c\n    codebooknewamp1.c\n    codebooknewamp1_energy.c' src/CMakeLists.txt

    mkdir build && cd build

    # Создаем "заглушку" для генератора кодов. 
    # не нужно ничего генерировать, так как в репо уже есть пред-сгенерированные файлы.
    # cat <<EOF > fake_gen
## !/bin/sh
# exit 0
# EOF
    # chmod +x fake_gen

    # вырезаем ExternalProject, который мучает билд
    # Удаляем все упоминания codec2_native из всех файлов
    # find . -name "src/CMakeLists.txt" -exec sed -i '/codec2_native/d' {} +

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
        -DUNITTEST=OFF
        -DINSTALL_EXAMPLES=OFF
        # Дополнительные флаги для кросс-компиляции
        -DBUILD_TESTING=OFF
    )

    cmake "${mycmake[@]}" ..

    # Сборка только самой библиотеки (избегаем сборки демо-экзешников, которые и вызывают ошибку LD)
    # Нам нужен только libcodec2.a для FFmpeg
    make -j$(nproc) codec2 $MAKE_V

    # Ручная установка, если 'make install' захочет собрать c2enc/c2dec
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib"
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/codec2"
    cp src/libcodec2.a "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
    cp ../src/codec2.h "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/codec2/"
    
    # Создаем pkg-config файл вручную, так как стандартный может не создаться без полной установки
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
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

    log_info "SUCCESS: libcodec2.a and pkgconfig manually prepared."

    # Проверяем, создалась ли библиотека и есть ли в ней символы
    # if ${FFBUILD_CROSS_PREFIX}nm src/libcodec2.a | grep -q "lsp_cb"; then
        # log_info "Codec2 library looks good (symbols found)."
    # else
        # log_warn "Symbols missing in libcodec2.a, forcing object compilation..."
        # Если символов нет, принудительно компилируем codebook.c из папки src
        # for f in ../src/codebook*.c; do
            # ${CC} ${CFLAGS} -c "$f" -o "src/$(basename $f).obj"
            # ${AR} rcs src/libcodec2.a "src/$(basename $f).obj"
        # done
    # fi

    # make install DESTDIR="$FFBUILD_DESTDIR"

    # Проверка результата (важно для отладки)
    if [[ -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libcodec2.a" ]]; then
        log_info "SUCCESS: libcodec2.a created."
    else
        log_error "FAILURE: libcodec2.a not found in destdir."
        ls -R "$FFBUILD_DESTDIR"
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
