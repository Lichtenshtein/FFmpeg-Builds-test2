#!/bin/bash
SCRIPT_REPO="https://github.com/lensfun/lensfun.git"
SCRIPT_COMMIT="a6d6fd5b95cbeb98479b62e9644a06b78b916bd8"

ffbuild_depends() {
    echo base
    echo glib2
    echo libpng
    echo libxml2
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # python3 -m pip install build --break-system-packages

    mkdir build && cd build

    # нужно передать ДВА пути к инклудам Glib
    local GLIB_INCLUDES="-I$FFBUILD_PREFIX/include/glib-2.0 -I$FFBUILD_PREFIX/lib/glib-2.0/include"

    local mycmake=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        # Добавляем пути к glibconfig.h через C_FLAGS
        -DBUILD_STATIC=ON
        -DBUILD_TESTS=OFF
        -DBUILD_LENSTOOL=OFF
        -DBUILD_DOC=OFF
        -DBUILD_FOR_SSE=ON
        -DBUILD_FOR_SSE2=ON
        -DINSTALL_HELPER_SCRIPTS=OFF
        # Отключаем Python принудительно
        -DPYTHON_EXECUTABLE=OFF
        # Уточняем пути для CMake-модуля поиска Glib
        -DGLIB2_LIBRARIES="$FFBUILD_PREFIX/lib/libglib-2.0.a"
        -DGLIB2_BASE_INCLUDE_DIR="$FFBUILD_PREFIX/include/glib-2.0"
        -DGLIB2_INTERNAL_INCLUDE_DIR="$FFBUILD_PREFIX/lib/glib-2.0/include"
    )

    CFLAGS="$CFLAGS $CPPFLAGS $GLIB_INCLUDES" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS $GLIB_INCLUDES" \
    LDFLAGS="$LDFLAGS" \
    cmake "${mycmake[@]}" .. || return 1
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local pc_file="$PC_DIR/lensfun.pc"
    if [[ -f "$pc_file" ]]; then
        log_info "Patching lensfun.pc for static MinGW build..."
        # Добавляем glib-2.0 в зависимости, чтобы пути -I подтянулись автоматически
        if ! grep -q "Requires:" "$pc_file"; then
            echo "Requires: glib-2.0" >> "$pc_file"
        else
            sed -i '/^Requires:/ s/$/ glib-2.0/' "$pc_file"
        fi
    fi

}

ffbuild_configure() { echo --enable-liblensfun; }
ffbuild_unconfigure() { echo --disable-liblensfun; }
