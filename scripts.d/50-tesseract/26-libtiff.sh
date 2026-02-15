#!/bin/bash

SCRIPT_REPO="https://github.com/libsdl-org/libtiff.git"
SCRIPT_COMMIT="258102cceb42584ee29abba411a0a609f4c432a9"

ffbuild_depends() {
    echo zlib
    echo libjpeg-turbo
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/libtiff" ]]; then
        for patch in /builder/patches/libtiff/*.patch; do
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

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -Djpeg=ON
        -Dzlib=ON
        -Dlzma=ON
        -Dwebp=OFF # Чтобы избежать круговой зависимости с libwebp
    )

    cmake "${myconf[@]}" -DCMAKE_C_FLAGS="$CFLAGS" ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    return 0
}
