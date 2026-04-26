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

    # Исправляем configure, чтобы он не игнорировал внешние CFLAGS (частая беда xavs)
    sed -i 's/CFLAGS="$CFLAGS -Wall/CFLAGS="$CFLAGS -Wall $EXTRA_CFLAGS/' configure

    sed -i 's/AS="nasm"/AS="nasm -f win64"/g' configure

    sed -i 's/\/\*#ifdef HAVE_MMXEXT/#ifdef HAVE_MMXEXT/g' common/mc.c
    sed -i 's/#include "i386\/mc.h"/#include "i386\/mc.h"/g' common/mc.c
    sed -i 's/#endif\*\/ /#endif/g' common/mc.c

    mkdir -p common/i386
    cat <<EOF > common/i386/mc.h
#ifndef XAVS_I386_MC_H
#define XAVS_I386_MC_H
#include "../common.h"
void xavs_mc_chroma_mmxext(uint8_t *src, int i_src_stride, uint8_t *dst, int i_dst_stride, int d8x, int d8y, int i_width, int i_height);
void xavs_mc_mmxext_init(xavs_mc_functions_t *pf);
void xavs_mc_sse2_init(xavs_mc_functions_t *pf);
#endif
EOF

    local myconf=(
        --host="$FFBUILD_TOOLCHAIN"
        --cross-prefix="$FFBUILD_CROSS_PREFIX"
        --prefix="$FFBUILD_PREFIX"
        --enable-asm
        --enable-pthread
        --enable-pic
    )

    [[ "${PREFER_SHARED}" == "1" ]] && myconf+=( --enable-shared )

    if [[ $TARGET == win* ]]; then
        export AS="nasm"
        export CC="${FFBUILD_CROSS_PREFIX}gcc"
        export AR="${FFBUILD_CROSS_PREFIX}ar"
        export RANLIB="${FFBUILD_CROSS_PREFIX}ranlib"
        export ASFLAGS="-f win64 -DARCH_X86_64=1"
    fi

    ./configure "${myconf[@]}" \
        --extra-cflags="$CFLAGS $CPPFLAGS ${NOLTO} -Wno-error=implicit-function-declaration -Wno-unused-const-variable -Wno-unused-function -Wno-error=incompatible-pointer-types -fno-strict-aliasing -Wno-array-bound -fcommon" \
        --extra-ldflags="$LDFLAGS ${NOLTO}" || return 1

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
