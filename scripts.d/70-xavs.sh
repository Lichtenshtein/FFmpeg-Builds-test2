#!/bin/bash

SCRIPT_REPO="https://github.com/cntrump/xavs.git"
SCRIPT_COMMIT="1df4f285b28c5296d050bfa1d7a7520143f3f4ce"

# SCRIPT_REPO="https://svn.code.sf.net/p/xavs/code/trunk"
# SCRIPT_REV="55"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # sed -i '/#include <stdio.h>/a #include "common/i386/mc.h"' common/mc.c

    sed -i 's/dct\[0\]\[y\*8+x\]/dct[y][x]/g' common/dct.c

    sed -i 's/dctf->sub8x8_dct8 = xavs_sub8x8_dct8_sse2/dctf->sub8x8_dct8 = (void (*)(int16_t (*)[8], uint8_t *, uint8_t *))xavs_sub8x8_dct8_sse2/g' common/dct.c
    sed -i 's/dctf->sub16x16_dct8 = xavs_sub16x16_dct8_sse2/dctf->sub16x16_dct8 = (void (*)(int16_t (*)[8][8], uint8_t *, uint8_t *))xavs_sub16x16_dct8_sse2/g' common/dct.c
    sed -i 's/dctf->add8x8_idct8 = xavs_add8x8_idct8_sse2/dctf->add8x8_idct8 = (void (*)(uint8_t *, int16_t (*)[8]))xavs_add8x8_idct8_sse2/g' common/dct.c
    sed -i 's/dctf->add16x16_idct8 = xavs_add16x16_idct8_sse2/dctf->add16x16_idct8 = (void (*)(uint8_t *, int16_t (*)[8][8]))xavs_add16x16_idct8_sse2/g' common/dct.c

    sed -i 's/CFLAGS="-O4 -ffast-math $CFLAGS"/CFLAGS="$CFLAGS"/g' configure
    sed -i 's/AS="yasm"/AS="nasm"/g' configure
    sed -i 's/ASFLAGS="$ASFLAGS -f win32 -m amd64 -DPREFIX"/ASFLAGS="$ASFLAGS -f win64 -DPIC"/g' configure

    mkdir -p common/i386
    cat <<EOF > common/i386/mc.h
#ifndef XAVS_I386_MC_H
#define XAVS_I386_MC_H
#include <stdint.h>

void xavs_mc_chroma_mmxext(uint8_t *src, int i_src_stride, uint8_t *dst, int i_dst_stride, int d8x, int d8y, int i_width, int i_height);
void xavs_mc_mmxext_init(void *pf);
void xavs_mc_sse2_init(void *pf);

#endif
EOF

    sed -i '/#include "common.h"/a #include "common/i386/mc.h"' common/mc.c

    local myconf=(
        --host="$FFBUILD_TOOLCHAIN"
        --cross-prefix="$FFBUILD_CROSS_PREFIX"
        --prefix="$FFBUILD_PREFIX"
        --enable-asm
        --enable-pthread
        --enable-pic
    )

    [[ "${PREFER_SHARED}" == "1" ]] && myconf+=( --enable-shared )

    export AS="nasm"
    export EXTRA_ASFLAGS="-I./common/i386/ -f win64 -DPIC -DARCH_X86_64=1 -DPREFIX"

    sed -i 's/AS="yasm"/AS="nasm"/g' configure
    sed -i 's/win32/win64/g' configure
    sed -i 's/-m amd64//g' configure

    ./configure "${myconf[@]}" \
        --extra-cflags="$CFLAGS $CPPFLAGS ${NOLTO} -fno-strict-aliasing -fcommon -Wno-error -Wno-maybe-uninitialized -Wno-array-bounds -fno-stack-protector -Wno-error=implicit-function-declaration -Wno-implicit-function-declaration -Wno-incompatible-pointer-types" \
        --extra-asflags="$EXTRA_ASFLAGS" \
        --extra-ldflags="$LDFLAGS ${NOLTO}" || return 1

    if [ -f config.mak ]; then
        sed -i 's/-m amd64//g' config.mak
        sed -i 's/-f win32/-f win64/g' config.mak
    fi

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/xavs.pc"
    if [[ ! -f "$PC_FILE" ]]; then
        log_info "Creating missing xavs.pc manually..."
        mkdir -p "$PC_DIR"
        cat <<EOF > "$PC_FILE"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: xavs
Description: AVS (Audio Video Standard) encoder library
Version: r$SCRIPT_REV
Libs: -L\${libdir} -lxavs
Cflags: -I\${includedir}
EOF
    fi
}

ffbuild_configure() {
    echo --enable-libxavs
}

ffbuild_unconfigure() {
    echo --disable-libxavs
}
