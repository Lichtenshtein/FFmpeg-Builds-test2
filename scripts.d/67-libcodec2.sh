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

    # Сначала полностью вырезаем проблемный блок ExternalProject
    # Мы заменяем его на пустышку, чтобы CMake не ругался на отсутствие цели generate_codebook
    sed -i '/if(CMAKE_CROSSCOMPILING)/,/endif(CMAKE_CROSSCOMPILING)/c\add_executable(generate_codebook IMPORTED)\nset_target_properties(generate_codebook PROPERTIES IMPORTED_LOCATION /usr/bin/true)' src/CMakeLists.txt

    mkdir build && cd build

    # В репозитории codec2 файлы кодовых книг лежат в папке 'src'.
    # Мы создадим в папке build симлинки на них, чтобы CMake их увидел как "сгенерированные"
    for f in ../src/codebook*.c; do
        ln -sf "$f" "$(basename "$f")"
    done

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DUNITTEST=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake "${myconf[@]}" .. || return 1

    # Сборка только библиотеки
    if ! make -j$(nproc) codec2 $MAKE_V; then
        log_warn "${XCLAM_MARK} Standard make failed, performing manual object compilation..."
        # Компилируем все .c файлы из папки src
        for f in ../src/*.c; do
            [[ "$f" == *"generate_codebook.c"* ]] && continue
            ${CC} ${CFLAGS} -I../src -I. -c "$f" -o "$(basename "${f%.c}.obj")"
        done
        ${AR} rcs src/libcodec2.a *.obj
    fi || return 1

    mkdir -p "$INSTALL_ROOT/lib"
    mkdir -p "$INSTALL_ROOT/include/codec2"
    mkdir -p "$PC_DIR"

    # Копируем библиотеку (проверяем оба возможных места появления)
    if [[ -f "src/libcodec2.a" ]]; then
        cp src/libcodec2.a "$INSTALL_ROOT/lib/libcodec2.a"
    elif [[ -f "libcodec2.a" ]]; then
        cp libcodec2.a "$INSTALL_ROOT/lib/libcodec2.a"
    fi

    # Копируем заголовочные файлы
    cp ../src/codec2.h "$INSTALL_ROOT/include/codec2/"
    cp ../src/fsk.h ../src/fdmdv.h "$INSTALL_ROOT/include/codec2/" 2>/dev/null || true

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
    if [[ -f "$INSTALL_ROOT/lib/libcodec2.a" ]]; then
        log_info "${CHECK_MARK} SUCCESS: libcodec2.a is ready."
    else
        log_error "libcodec2.a still missing in $INSTALL_ROOT/lib/"
        return 1
    fi
}

ffbuild_configure() {
    echo --enable-libcodec2
}

ffbuild_unconfigure() {
    echo --disable-libcodec2
}
