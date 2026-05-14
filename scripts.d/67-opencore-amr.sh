#!/bin/bash

SCRIPT_REPO="https://github.com/arthenica/opencore-amr.git"
SCRIPT_COMMIT="7dba8c32238418ce0b316a852b2224df586ca896"

SCRIPT_MIRROR="https://git.code.sf.net/p/opencore-amr/code"
SCRIPT_MIRROR_COMMIT="7dba8c32238418ce0b316a852b2224df586ca896"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    autoreconf -i

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --with-pic
      # --enable-gcc-armv # enable GCC specific ARMv5 assembler
        --enable-compile-c
        --enable-amrnb-encoder
        --enable-amrnb-decoder
        --disable-examples
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    fi

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    mkdir -p "$PC_DIR"
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s|^Cflags:.*|& -I\${includedir}/opencore-amrnb|" "$PC_FILE"
        done
        log_info "Cflags paths have been updated."
    fi
}

ffbuild_configure() {
    echo --enable-libopencore-amrnb --enable-libopencore-amrwb
}

ffbuild_unconfigure() {
    echo --disable-libopencore-amrnb --disable-libopencore-amrwb
}
