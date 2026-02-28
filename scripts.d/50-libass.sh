#!/bin/bash

# SCRIPT_REPO="https://github.com/libass/libass.git"
# SCRIPT_COMMIT="fadc390583f24eb5cf98f16925fd3adee50bca88"

SCRIPT_REPO="https://github.com/amanosatosi/libassmod.git"
SCRIPT_COMMIT="beb9f3960b022a2f51cd08ddc9c39fa29b30b5af"

ffbuild_depends() {
    echo base
    echo libiconv
    echo freetype
    echo fontconfig
    echo harfbuzz
    echo fribidi
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/libass" ]]; then
        for patch in /builder/patches/libass/*.patch; do
            log_info "APPLYING PATCH: $patch"
            if patch -p1 -N -r - -l < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
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
        --enable-wrap-unicode
        --enable-directwrite
    )

    export CFLAGS="$CFLAGS -Dread_file=libass_internal_read_file"

    ./configure "${myconf[@]}"
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libass
}

ffbuild_unconfigure() {
    echo --disable-libass
}
