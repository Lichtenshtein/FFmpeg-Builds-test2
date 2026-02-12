#!/bin/bash
SCRIPT_REPO="https://github.com/libffi/libffi.git"
SCRIPT_COMMIT="v3.4.6"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    # Вместо ./autogen.sh используем это, чтобы избежать ошибок макросов
    autoreconf -i -f -v

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-static
        --disable-shared
        --with-pic
        --disable-docs
        --disable-multi-os-directory # Критично для MinGW, чтобы не создавал папки ../lib64
    )

    ./configure "${myconf[@]}"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Хак для некоторых пакетов, которые ищут ffi.h в неправильном месте
    # (libffi любит прятать заголовки в lib/libffi-3.4.6/include)
    if [[ -d "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libffi-$SCRIPT_COMMIT/include" ]]; then
        cp -r "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libffi-$SCRIPT_COMMIT/include"/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"
    fi
}
