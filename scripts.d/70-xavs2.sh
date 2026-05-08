#!/bin/bash

SCRIPT_REPO="https://github.com/pkuvcl/xavs2.git"
SCRIPT_COMMIT="eae1e8b9d12468059bdd7dee893508e470fa83d8"

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    [[ $TARGET == win32 ]] && return 1
    # xavs2 aarch64 support is broken
    [[ $TARGET == *arm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    export SKIP_POST_STRIP=1

    find source -name "*.c" -exec sed -i 's/#define __int64 int64_t/\/\/ #define __int64 int64_t/g' {} +

    cd /build/${STAGENAME}/build/linux

    # Фикс для современных компиляторов (json11)
    # Ищем файл во всем дереве, так как путь может варьироваться
    find . -name "json11.cpp" -exec sed -i '1i#include <cstdint>' {} +
    find . -name "api.cpp" -exec sed -i 's/payload = NULL;//g' {} +

    # Фикс проверки endianness
    sed -i -e 's/EGIB/bss/g' -e 's/naidnePF/bss/g' configure

    sed -i 's/HIGH_BIT_DEPTH=NO/HIGH_BIT_DEPTH=YES/g' configure || true
    sed -i 's/high_bit_depth="no"/high_bit_depth="yes"/g' configure
    sed -i '/BitDepth $bit_depth not supported currently./d' configure
    sed -i '/exit 1/ { N; /BitDepth/d }' configure

    local myconf=(
        --disable-cli
        --enable-pic
        --enable-strip
        --bit-depth=8
        --chroma-format=all
        --disable-avs
        --disable-swscale
        --disable-lavf
        --disable-ffms
        --disable-gpac
        --disable-lsmash
        --extra-asflags="-w-macro-params-legacy -DARCH_X86_64=1"
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --cross-prefix="$FFBUILD_CROSS_PREFIX"
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --enable-shared ) || \
        myconf+=( --enable-static )
    # [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    if [[ $TARGET == win* ]]; then
        export AS="nasm"
    fi

    ./configure "${myconf[@]}" \
        --extra-cflags="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Wno-tautological-compare -Wno-discarded-qualifiers -Wno-array-parameter -Wno-missing-braces" \
        --extra-ldflags="$LDFLAGS ${USELTO}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/xavs2.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        sed -i '/^Libs.private:/ s/$/ -lstdc++ -lm/' "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libxavs2
}

ffbuild_unconfigure() {
    echo --disable-libxavs2
}
