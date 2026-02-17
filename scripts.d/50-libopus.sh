#!/bin/bash

SCRIPT_REPO="https://github.com/xiph/opus.git"
SCRIPT_COMMIT="59f13a3eb0eed3a56cf46bd68cc2f29f18d83ba2"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .

    # This is where they decided to put downloads for external dependencies, so it needs to run here
    # Fix freaking 11000 lines of dot wall
    echo "WGETRC=/dev/null wget -q --show-progress --progress=bar:force ./autogen.sh"
    # echo "alias wget='wget -q --show-progress --progress=bar:force' && alias curl='curl -fsSL' && ./autogen.sh"
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/libopus" ]]; then
        for patch in /builder/patches/libopus/*.patch; do
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

    # re-run autoreconf explicitly because tools versions might have changed since it generared the dl cache
    autoreconf -isf

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --disable-extra-programs
    )

    if [[ $TARGET == winarm* ]]; then
        myconf+=(
            --disable-rtcd
        )
    fi

    ./configure "${myconf[@]}"
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libopus
}

ffbuild_unconfigure() {
    echo --disable-libopus
}
