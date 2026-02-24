#!/bin/bash

SCRIPT_REPO="https://github.com/AviSynth/AviSynthPlus.git"
SCRIPT_COMMIT="8f2a77887874a9c78fc3524b1feafbb69011bfc2"

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/avisynth" ]]; then
        for patch in "/builder/patches/avisynth"/*.patch; do
            log_info "-----------------------------------"
            log_info "APPLYING PATCH: $patch"
            if patch -p1 < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
                log_info "-----------------------------------"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                log_error "-----------------------------------"
                # return 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi
    # their version check is insistant on a tag to exist, so make one
    git tag -a ffbuild -m "FFbuild Version"

    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DHEADERS_ONLY=ON ..
    make -j$(nproc) $MAKE_V
    make VersionGen install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-avisynth
}

ffbuild_unconfigure() {
    echo --disable-avisynth
}
