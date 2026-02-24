#!/bin/bash

SCRIPT_REPO="https://github.com/netony/davs2.git"
SCRIPT_COMMIT="0a9f952f09343156575e75a2d733d95529ba2d8a"


ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    [[ $TARGET == win32 ]] && return 1
    # davs2 aarch64 support is broken
    [[ $TARGET == *arm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    # echo "git fetch --unshallow"
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/zimg" ]]; then
        for patch in "/builder/patches/zimg"/*.patch; do
            log_info "\n-----------------------------------"
            log_info "~~~ APPLYING PATCH: $patch"
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

    cd build/linux

  # --enable-lto
    local myconf=(
        --disable-cli
        --enable-pic
        --prefix="$FFBUILD_PREFIX"
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
            --cross-prefix="$FFBUILD_CROSS_PREFIX"
        )
    else
        echo "Unknown target"
        return 1
    fi

    # Work around configure endian check failing on modern gcc/binutils.
    # Assumes all supported archs are little endian.
    sed -i -e 's/EGIB/bss/g' -e 's/naidnePF/bss/g' configure

    ./configure "${myconf[@]}"
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libdavs2
}

ffbuild_unconfigure() {
    echo --disable-libdavs2
}
