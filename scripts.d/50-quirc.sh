#!/bin/bash

SCRIPT_REPO="https://github.com/dlbeer/quirc.git"
SCRIPT_COMMIT="927d680904dc95fdff4cd9d022eb374b438ff8f2"

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return -1
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/quirc" ]]; then
        for patch in /builder/patches/quirc/*.patch; do
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

    # Явно передаем инструменты, чтобы quirc не собрался под хост (Linux)
    make libquirc.a $MAKE_V -j$(nproc) CC="$CC" AR="$AR" CFLAGS="$CFLAGS"
    
    mkdir -p "$FFBUILD_DESTPREFIX/lib/" "$FFBUILD_DESTPREFIX/include/"
    cp libquirc.a "$FFBUILD_DESTPREFIX/lib/"
    cp lib/quirc.h "$FFBUILD_DESTPREFIX/include/"
}

ffbuild_configure() {
    echo --enable-libquirc
}

ffbuild_unconfigure() {
    echo --disable-libquirc
}

ffbuild_cflags() {
    return 0
}

ffbuild_ldflags() {
    return 0
}
