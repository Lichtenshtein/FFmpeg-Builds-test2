#!/bin/bash

SCRIPT_REPO="https://svn.code.sf.net/p/lame/svn/trunk/lame"
SCRIPT_REV="6531"

ffbuild_depends() {
    echo base
    echo libiconv
}

ffbuild_enabled() {
    return 0
}

# ffbuild_dockerdl() {
    # echo "retry-tool sh -c \"rm -rf lame && svn checkout '${SCRIPT_REPO}@${SCRIPT_REV}' lame\" && cd lame"
# }

ffbuild_dockerdl() {
    echo "retry-tool svn checkout '${SCRIPT_REPO}@${SCRIPT_REV}' ."
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/libmp3lame" ]]; then
        for patch in /builder/patches/libmp3lame/*.patch; do
            echo "Applying $patch"
            git apply "$patch" || patch -p1 < "$patch"
        done
    fi

    autoreconf -i

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --enable-nasm
        --disable-gtktest
        --disable-cpml
        --disable-frontend
        --disable-decoder
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    export CFLAGS="$CFLAGS -DNDEBUG -D_ALLOW_INTERNAL_OPTIONS -Wno-error=incompatible-pointer-types"

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libmp3lame
}

ffbuild_unconfigure() {
    echo --disable-libmp3lame
}
