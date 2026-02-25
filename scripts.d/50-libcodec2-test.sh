#!/bin/bash

# SCRIPT_REPO="https://github.com/arancormonk/codec2.git"
# SCRIPT_COMMIT="6a787012632b8941aa24a4ea781440b61de40f57"

# SCRIPT_REPO2="https://github.com/rhythmcache/codec2.git"
# SCRIPT_COMMIT2="6e0a0e09c065aa5401eb9c30d724240fffe890f1"

# SCRIPT_REPO3="https://github.com/zups/codec2.git"
# SCRIPT_COMMIT3="371c82ae557f1b033cf4b625be435bb4b88ef70b"

# SCRIPT_REPO="https://github.com/Alex-Pennington/codec2.git"
# SCRIPT_COMMIT="19571e0a2b42340597fd762803f6eb9d030ee4c5"

SCRIPT_REPO="https://github.com/drowe67/codec2.git"
SCRIPT_COMMIT="96e8a19c2487fd83bd981ce570f257aef42618f9"

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

    # Создаем "заглушку" для генератора кодов. 
    # не нужно ничего генерировать, так как в репо уже есть пред-сгенерированные файлы.
    # cat <<EOF > fake_gen
## !/bin/sh
# exit 0
# EOF
    # chmod +x fake_gen

    # вырезаем ExternalProject, который мучает билд
    # Удаляем все упоминания codec2_native из всех файлов
    # find . -name "CMakeLists.txt" -exec sed -i '/codec2_native/d' {} +

    mkdir build && cd build

    local mycmake=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_C_FLAGS="$CFLAGS"
        -DCMAKE_CXX_FLAGS="$CXXFLAGS"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
        -DBUILD_SHARED_LIBS=OFF
        # -DGENERATE_CODEBOOK="$(pwd)/../fake_gen"
        -DUNITTEST=OFF
        -DINSTALL_EXAMPLES=OFF
        # Дополнительные флаги для кросс-компиляции
        -DBUILD_TESTING=OFF
    )

    cmake "${mycmake[@]}" ..

    # Мы позволяем ExternalProject создаться, но подменяем результат
    # Создаем структуру папок, которую ожидает ошибочная команда копирования
    mkdir -p src/codec2_native/src
    
    # Создаем пустой файл, который CMake пытается скопировать
    # Это предотвратит ошибку "Error copying file"
    touch src/codec2_native/src/generate_codebook
    chmod +x src/codec2_native/src/generate_codebook

    # Теперь запускаем сборку. Даже если он попробует собрать настоящий 
    # generate_codebook.exe, наш пустой файл без расширения уже будет лежать на месте.
    make -j$(nproc) codec2 || true
    
    # Повторный проход на случай, если параллельная сборка что-то пропустила
    # и финальное "затыкание" дыр
    touch src/generate_codebook

    make -j$(nproc) codec2 $MAKE_V
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
