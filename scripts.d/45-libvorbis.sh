#!/bin/bash

SCRIPT_REPO="https://github.com/xiph/vorbis.git"
SCRIPT_COMMIT="2d79800b6751dddd4b8b4ad50832faa5ae2a00d9"

ffbuild_depends() {
    echo base
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/libvorbis" ]]; then
        for patch in /builder/patches/libvorbis/*.patch; do
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
        --disable-oggtest
        --disable-docs
        --disable-examples
    )

    ./configure "${myconf[@]}"
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libvorbis
}

ffbuild_unconfigure() {
    echo --disable-libvorbis
}
