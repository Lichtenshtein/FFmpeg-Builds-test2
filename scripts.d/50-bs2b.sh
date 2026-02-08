#!/bin/bash

SCRIPT_REPO="https://github.com/alexmarsev/libbs2b.git"
SCRIPT_COMMIT="5ca2d59888df047f1e4b028e3a2fd5be8b5a7277"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerstage() {
    to_df "RUN --mount=src=${SELF},dst=/stage.sh --mount=src=${SELFCACHE},dst=/cache.tar.xz --mount=src=patches/bs2b,dst=/patches run_stage /stage.sh"
}

ffbuild_dockerbuild() {
    for patch in /patches/*.patch; do
        echo "Applying $patch"
        patch -p1 < "$patch"
    done

    autoreconf -if

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --with-pic
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libbs2b
}

ffbuild_unconfigure() {
    echo --disable-libbs2b
}
