#!/bin/bash
SCRIPT_REPO="https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "curl -sL \"$SCRIPT_REPO\" --output libffi.tar.gz && tar xzf libffi.tar.gz --strip-components=1"
}

ffbuild_dockerbuild() {
    # Вместо ./autogen.sh используем это, чтобы избежать ошибок макросов
    ./configure \
        --prefix="$FFBUILD_PREFIX" \
        --host="$FFBUILD_TOOLCHAIN" \
        --enable-static \
        --disable-shared \
        --disable-docs \
        --disable-multi-os-directory

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем пути инклудов
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include"
    cp -r "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/lib/libffi-*/include/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/" 2>/dev/null || true
}
