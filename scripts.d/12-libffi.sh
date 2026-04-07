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
    set -e

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-docs
        --with-gcc-arch=${CPU_ARCH:-broadwell}
        --disable-multi-os-directory
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    CPPFLAGS="$CPPFLAGS -DFFI_STATIC_BUILD" \
    CXXFLAGS="$CXXFLAGS -DFFI_STATIC_BUILD" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Переносим хедеры в корень include, чтобы glib их увидел
    # libffi по умолчанию прячет их в /lib/libffi-3.5.2/include
    local FFI_INC=$(find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "ffi.h" -printf "%h")
    if [[ -n "$FFI_INC" ]]; then
        mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include"
        cp -af "$FFI_INC"/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"
    fi
    local PC_FILE="$PC_DIR/libffi.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "/^Cflags:/ s/$/ -DFFI_STATIC_BUILD/" "$PC_FILE"
    fi

}
