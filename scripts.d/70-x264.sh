#!/bin/bash
export USE_VERS_FINDER=1
# SCRIPT_REPO="https://code.videolan.org/videolan/x264.git"
# SCRIPT_COMMIT="0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee"

# SCRIPT_REPO="https://github.com/jpsdr/x264.git"
# SCRIPT_COMMIT="ba817a33001f0179d5905eb25b8b64214d95341c"
# SCRIPT_BRANCH="t_mod_New"

SCRIPT_REPO="https://github.com/neil1123-cc/x264.git"
SCRIPT_COMMIT="2d0302bb5665ca3716bb5370cbfbf8a2a2475e6e"

SCRIPT_REPO4="https://github.com/Olde-Skuul/quicktime7windows.git"
SCRIPT_COMMIT4="8c1181141c1e08ed6b26335238b6d1fc0e065b12"
SCRIPT_DIR4="quicktime"

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf quicktime/samples"
}

ffbuild_dockerbuild() {
    set -e

    # if [[ ! -d ".git" ]]; then
        # log_info "Creating x264 version metadata manually..."
        # echo "#define X264_REV 3214" > x264_config.h
        # echo "#define X264_REV_DIFF 0" >> x264_config.h
        # echo "#define X264_VERSION \" r3214 0480cb0\"" >> x264_config.h
        # echo "#define X264_VER \"165\"" >> x264_config.h
    # fi

    if [[ ! -d ".git" ]]; then
        log_info "Creating x264 version metadata manually..."
        export VER_FULL="${VER_FULL}"
        cat << 'EOF' > version.sh
#!/usr/bin/env bash

PLAIN_VER="${VER_FULL}"
VER_DIFF="0"

BIT_DEPTH=$(grep "X264_BIT_DEPTH" < x264_config.h | awk '{print $3}')
if [ "$BIT_DEPTH" == "0" ] || [ -z "$BIT_DEPTH" ] ; then
    BIT_DEPTH="all"
fi

CHROMA_FORMATS=$(grep "X264_CHROMA_FORMAT" < x264_config.h | awk '{print $3}')
if [ "$CHROMA_FORMATS" == "0" ] || [ -z "$CHROMA_FORMATS" ] ; then
    CHROMA_FORMATS="all"
fi

BUILD_ARCH=$(grep "SYS_ARCH=" < config.mak | awk -F= '{print $2}')
[ -z "$BUILD_ARCH" ] && BUILD_ARCH="X86_64"

echo "#define X264_REV $PLAIN_VER"
echo "#define X264_REV_DIFF $VER_DIFF"

VER="$PLAIN_VER ffbuild t_mod_New [${BIT_DEPTH}-bit@${CHROMA_FORMATS} ${BUILD_ARCH}]"
echo "#define X264_VERSION \" r$VER\""

API=$(grep '#define X264_BUILD' < "$(dirname "$0")"/x264.h | sed -e 's/.* \([1-9][0-9]*\).*/\1/')
echo "#define X264_POINTVER \"0.$API.$PLAIN_VER\""
EOF
    chmod +x version.sh
    fi

    local myconf=(
        --disable-cli
        --enable-pic
        --disable-lavf
        --disable-swscale
        --bit-depth=all
        --disable-win32thread
        --chroma-format=all
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --cross-prefix="$FFBUILD_CROSS_PREFIX"
        # fork settings
        --enable-nonfree
        --qtsdk="${PWD}/quicktime" # root of QuickTime SDK for QuickTime AAC support
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --enable-shared ) || \
        myconf+=( --enable-static )
    # [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    # явно указываем инструменты для стабильности
    export AS="nasm"
    export CC="${FFBUILD_CROSS_PREFIX}gcc"

    ./configure "${myconf[@]}" \
        --extra-cflags="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        --extra-ldflags="$LDFLAGS ${USELTO}" || return 1

    # если в config.log написано "asm: no", значит nasm не подцепился
    if grep -q "asm: no" config.log; then
        log_error "x264 configured WITHOUT assembly! Check config.log."
        return 1
    fi

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/x264.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i 's|^Cflags:.*|Cflags: -I${includedir}|' "$PC_FILE"
        sed -i "s|-L$FFBUILD_PREFIX/lib|-L\${libdir}|g" "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libx264
}

ffbuild_unconfigure() {
    echo --disable-libx264
}
