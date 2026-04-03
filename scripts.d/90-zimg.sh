#!/bin/bash

SCRIPT_REPO="https://github.com/sekrit-twc/zimg.git"
SCRIPT_COMMIT="df9c1472b9541d0e79c8d02dae37fdf12f189ec2"

ffbuild_enabled() {
    return 0
}

ffbuild_depends() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e
    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
        --enable-simd
        --disable-testapp
        --disable-unit-test
        --disable-example
    )

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Исправляем .pc файл для статической линковки в FFmpeg
    local PC_FILE="$PC_DIR/zimg.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Гарантируем, что FFmpeg увидит необходимость линковки с libstdc++
        if ! grep -q "Libs.private" "$PC_FILE"; then
            echo "Libs.private: -lstdc++" >> "$PC_FILE"
        fi
    fi

}

ffbuild_configure() {
    echo --enable-libzimg
}

ffbuild_unconfigure() {
    echo --disable-libzimg
}
