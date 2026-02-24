#!/bin/bash

SCRIPT_REPO="https://github.com/kcat/openal-soft.git"
SCRIPT_COMMIT="266538011d2fc8ee875abed0be43a537d0e59743"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/openal" ]]; then
        for patch in /builder/patches/openal/*.patch; do
            log_info "-----------------------------------"
            log_info "APPLYING PATCH: $patch"
            if patch -p1 < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
                log_info "-----------------------------------"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                log_info "-----------------------------------"
                # return 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    mkdir cm_build && cd cm_build

    export CFLAGS="$CFLAGS -include stdlib.h"
    export CXXFLAGS="$CXXFLAGS -include cstdlib"

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DLIBTYPE=STATIC \
        -DALSOFT_UTILS=OFF \
        -DALSOFT_EXAMPLES=OFF  ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    echo "Libs.private: -lstdc++" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/openal.pc

    if [[ $TARGET == win* ]]; then
        echo "Libs.private: -lole32 -luuid" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/openal.pc
    fi
}

ffbuild_configure() {
    echo --enable-openal
}

ffbuild_unconfigure() {
    echo --disable-openal
}
