#!/bin/bash

SCRIPT_REPO="https://github.com/cntrump/xavs.git"
SCRIPT_COMMIT="1df4f285b28c5296d050bfa1d7a7520143f3f4ce"

# SCRIPT_REPO="https://svn.code.sf.net/p/xavs/code/trunk"
# SCRIPT_REV="55"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Исправляем configure, чтобы он не игнорировал внешние CFLAGS (частая беда xavs)
    sed -i 's/CFLAGS="$CFLAGS -Wall/CFLAGS="$CFLAGS -Wall $EXTRA_CFLAGS/' configure

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --enable-asm
        --enable-pthread
        --enable-pic
        --disable-debug
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --enable-shared ) || \
        myconf+=( --disable-shared )

    if [[ $TARGET == win* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
            --cross-prefix="$FFBUILD_CROSS_PREFIX"
        )
        export CC="${FFBUILD_CROSS_PREFIX}gcc"
        export AR="${FFBUILD_CROSS_PREFIX}ar"
        export RANLIB="${FFBUILD_CROSS_PREFIX}ranlib"
    fi

    ./configure "${myconf[@]}" \
        --extra-cflags="$CFLAGS $CPPFLAGS ${USELTO}" \
        --extra-ldflags="$LDFLAGS ${USELTO}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # xavs часто не создает корректный pkg-config файл или ставит его не туда.
    # Если xavs.pc отсутствует, FFmpeg его не найдет.
    if [[ ! -f "$PC_DIR/xavs.pc" ]]; then
        log_info "Creating missing xavs.pc manually..."
        mkdir -p "$PC_DIR"
        cat <<EOF > "$PC_DIR/xavs.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: xavs
Description: AVS (Audio Video Standard) encoder library
Version: r$SCRIPT_REV
Libs: -L\${libdir} -lxavs
Cflags: -I\${includedir}
EOF
    fi
}

ffbuild_configure() {
    echo --enable-libxavs
}

ffbuild_unconfigure() {
    echo --disable-libxavs
}
