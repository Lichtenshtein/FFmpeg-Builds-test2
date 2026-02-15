#!/bin/bash

SCRIPT_REPO="https://github.com/scimmia9286/aribb24.git"
SCRIPT_COMMIT="fa54dee41aa38560f02868b24f911a24c33780a8"
SCRIPT_BRANCH="add-multi-DRCS-plane"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/aribb24" ]]; then
        for patch in /builder/patches/aribb24/*.patch; do
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

    # Library switched to LGPL on master, but didn't bump version since.
    # FFmpeg checks for >1.0.3 to allow LGPL builds.
    sed -i 's/1.0.3/1.0.4/' configure.ac

    autoreconf -i

    # Явно указываем пути к pkg-config и инклудам
    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig"
    export CFLAGS="$CFLAGS -I$FFBUILD_PREFIX/include"
    export LDFLAGS="$LDFLAGS -L$FFBUILD_PREFIX/lib"

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
}

ffbuild_configure() {
    echo --enable-libaribb24
}

ffbuild_unconfigure() {
    echo --disable-libaribb24
}
