#!/bin/bash

SCRIPT_REPO="https://github.com/Brainiarc7/SVT-HEVC.git"
SCRIPT_COMMIT="ee950558a2e3d0f0e3d78365b61a8f6020bd24de"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return -1
    [[ $TARGET == *arm64 ]] && return -1
    return 0
}

fixarm64=()

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/svt-hevc" ]]; then
        for patch in /builder/patches/svt-hevc/*.patch; do
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

    mkdir build1 && cd build1

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DENABLE_AVX512=OFF \
        -DBUILD_SHARED_LIBS=OFF ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libsvthevc
}

ffbuild_unconfigure() {
    echo --disable-libsvthevc
}
