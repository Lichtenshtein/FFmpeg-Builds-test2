#!/bin/bash

SCRIPT_REPO="https://github.com/scimmia9286/aribb24.git"
SCRIPT_COMMIT="fa54dee41aa38560f02868b24f911a24c33780a8"
SCRIPT_BRANCH="add-multi-DRCS-plane"

ffbuild_depends() {
    echo libpng
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    apply_patches

    # Library switched to LGPL on master, but didn't bump version since.
    # FFmpeg checks for >1.0.3 to allow LGPL builds.
    sed -i 's/1.0.3/1.0.4/' configure.ac

    autoreconf -i

    # Явно указываем пути к pkg-config и инклудам
    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig"
    export CFLAGS="$CFLAGS -I$FFBUILD_PREFIX/include"
    export LDFLAGS="$LDFLAGS -L$FFBUILD_PREFIX/lib"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
    )

    ./configure "${myconf[@]}"
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libaribb24
}

ffbuild_unconfigure() {
    echo --disable-libaribb24
}
