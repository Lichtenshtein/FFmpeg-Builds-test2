#!/bin/bash

SCRIPT_REPO="https://github.com/PCRE2Project/pcre2.git"
SCRIPT_COMMIT="123424f8a2267aa12ef819c64744b9cea934e414"

ffbuild_depends() {
    echo zlib
    echo bzlib
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    ./autogen.sh

    local DEP_LIBS="-lbz2 -lz -pthread $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-pcre2-8
        #--enable-pcre2-16
        #--enable-pcre2-32
        --with-link-size=3
        --with-parens-nest-limit=500
        --enable-jit
        --enable-unicode
        --enable-newline-is-anycrlf
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DPCRE2_STATIC"

    CFLAGS="$CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $static_flags ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$DEP_LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    for pc in "$PC_DIR"/*pcre2*.pc; do
        [[ -e "$pc" ]] || continue
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$pc"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$pc"
            fi
        fi
        sed -i '/^Libs.private:/d' "$pc"
        echo "Libs.private: $DEP_LIBS" >> "$pc"
    done
}
