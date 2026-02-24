#!/bin/bash

SCRIPT_REPO="https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "download_file \"$SCRIPT_REPO\" \"libffi.tar.gz\""
    echo "tar xzf libffi.tar.gz --strip-components=1"
}

ffbuild_dockerbuild() {
    # Вместо ./autogen.sh используем это, чтобы избежать ошибок макросов
    ./configure \
        --prefix="$FFBUILD_PREFIX" \
        --host="$FFBUILD_TOOLCHAIN" \
        --enable-static \
        --disable-shared \
        --disable-docs \
        --with-gcc-arch=broadwell \
        --disable-multi-os-directory

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Переносим хедеры в корень include, чтобы glib их увидел
    # libffi по умолчанию прячет их в /lib/libffi-3.5.2/include
    local FFI_INC=$(find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "ffi.h" -printf "%h")
    if [[ -n "$FFI_INC" ]]; then
        mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include"
        cp -af "$FFI_INC"/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"
    fi
}
