#!/bin/bash

SCRIPT_REPO="https://github.com/fraunhoferhhi/vvdec"
SCRIPT_COMMIT="9a4349460e4c61232c3e2cfabecb508616ae8c2f"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return -1
    [[ $TARGET == winarm* ]] && return -1
    (( $(ffbuild_ffver) > 700 )) || return -1
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/libvvdec" ]]; then
        for patch in /builder/patches/libvvdec/*.patch; do
            log_info "\n-----------------------------------"
            log_info "~~~ APPLYING PATCH: $patch"
            if patch -p1 < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
                log_info "-----------------------------------"
            else
                log_info "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                log_info "-----------------------------------"
                # exit 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    mkdir build && cd build

    export CFLAGS="$CFLAGS -fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"
    export CXXFLAGS="$CXXFLAGS -fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
         -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
         -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_C_FLAGS="$CFLAGS" \
         -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
         -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
         -DBUILD_SHARED_LIBS=OFF \
         -DEXTRALIBS="-lstdc++" \
         -DVVDEC_ENABLE_LINK_TIME_OPT=ON ..

# -DVVDEC_ENABLE_LINK_TIME_OPT=OFF

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libvvdec
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 700 )) || return 0
    echo --disable-libvvdec
}