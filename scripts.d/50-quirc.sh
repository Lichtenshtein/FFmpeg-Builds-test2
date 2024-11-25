#!/bin/bash

SCRIPT_REPO="https://github.com/dlbeer/quirc"

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return -1
    return 0
}

ffbuild_dockerstage() {
	to_df "RUN --mount=src=${SELF},dst=/stage.sh --mount=src=${SELFCACHE},dst=/cache.tar.xz --mount=src=patches/quirc,dst=/patches run_stage /stage.sh"
}

ffbuild_dockerbuild() {

    for patch in /patches/*.patch; do
        echo "Applying $patch"
        patch -p1 < "$patch"
    done

    export CC="$CC"
    export CFLAGS="$CFLAGS"

    make libquirc.a -j$(nproc)
    cp libquirc.a "$FFBUILD_PREFIX/lib/"
    cp lib/quirc.h "$FFBUILD_PREFIX/include/"
}

ffbuild_configure() {
    echo --enable-libquirc
}

ffbuild_unconfigure() {
    echo --disable-libquirc
}

ffbuild_cflags() {
    return 0
}

ffbuild_ldflags() {
    return 0
}
