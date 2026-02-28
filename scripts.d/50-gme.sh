#!/bin/bash

SCRIPT_REPO="https://github.com/libgme/game-music-emu.git"
SCRIPT_COMMIT="bb58c4a9a9ba847fc8f423aec8ffe9eb957baadf"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/gme" ]]; then
        for patch in /builder/patches/gme/*.patch; do
            log_info "APPLYING PATCH: $patch"
            if patch -p1 -N -r - -l < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                # return 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_DISABLE_FIND_PACKAGE_SDL2=1 \
        -DBUILD_SHARED_LIBS=OFF \
        -DGME_BUILD_STATIC=ON \
        -DGME_BUILD_FRAMEWORK=OFF \
        -DGME_BUILD_TESTING=OFF \
        -DGME_BUILD_EXAMPLES=OFF \
        -DGME_SPC_ISOLATED_ECHO_BUFFER=ON \
        -DGME_ZLIB=ON \
        -DENABLE_UBSAN=OFF ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libgme
}

ffbuild_unconfigure() {
    echo --disable-libgme
}
