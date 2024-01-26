#!/bin/bash

SCRIPT_REPO="https://github.com/festvox/flite"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerstage() {
    to_df "RUN --mount=src=${SELF},dst=/stage.sh --mount=src=patches/flite,dst=/patches run_stage /stage.sh"
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
    make install
}

ffbuild_configure() {
    echo --enable-libflite
}

ffbuild_unconfigure() {
    echo --disable-libflite
}
