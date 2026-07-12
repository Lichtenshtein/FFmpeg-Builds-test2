#!/bin/bash

SCRIPT_REPO="https://github.com/libcdio/libcdio.git"
SCRIPT_COMMIT="fe4f6077d8ea165e65552218d9aeff23684c23d7"

# SCRIPT_REPO2="https://git.savannah.gnu.org/git/libcdio.git"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf doc test example"
}

ffbuild_dockerbuild() {
    set -e

    autoreconf -if

    # вставляем макросы прямо в заголовочный файл, который включают все
    find include/cdio -name "*.h" -exec sed -i '1i#ifndef _POSIX_C_SOURCE\n#define _POSIX_C_SOURCE 199309L\n#endif' {} +

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-pic
        --disable-maintainer-mode
        --disable-example-progs
        --without-cd-drive
        --without-cd-info
        --without-cdda-player
        --without-cd-read
        --without-iso-info
        --without-iso-read
        --disable-cpp-progs
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS -D_POSIX_C_SOURCE=199309L" \
    CXXFLAGS="$CXXFLAGS -D_POSIX_C_SOURCE=199309L ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V MAKEINFO=true || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" MAKEINFO=true || return 1

    mkdir -p "$PC_DIR"
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s|^Cflags:.*|& -I\${includedir}/cdio|" "$PC_FILE"
        done
        log_info "Cflags paths have been updated."
    fi
}
