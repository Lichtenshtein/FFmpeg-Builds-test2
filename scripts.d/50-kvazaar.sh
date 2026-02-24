#!/bin/bash

SCRIPT_REPO="https://github.com/ultravideo/kvazaar.git"
SCRIPT_COMMIT="45597d8de2e3ef7695ac54e8a3372572c4bb8213"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/kvazaar" ]]; then
        for patch in /builder/patches/kvazaar/*.patch; do
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

    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
    )

    ./configure "${myconf[@]}"
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    echo "Cflags.private: -DKVZ_STATIC_LIB" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/kvazaar.pc
    echo "Libs.private: -lpthread" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/kvazaar.pc
}

ffbuild_configure() {
    echo --enable-libkvazaar
}

ffbuild_unconfigure() {
    echo --disable-libkvazaar
}
