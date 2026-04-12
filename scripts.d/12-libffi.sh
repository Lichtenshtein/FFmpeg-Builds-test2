#!/bin/bash

SCRIPT_REPO="https://github.com/libffi/libffi.git"
SCRIPT_COMMIT="170bab47c90626a33cd08f2169034600cfd9589c"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    # echo "download_file \"$SCRIPT_REPO\" \"libffi.tar.gz\""
    # echo "tar xzf libffi.tar.gz --strip-components=1"
}

ffbuild_dockerbuild() {
    set -e

    # export USE_CONF_FINDER=1

    cd "/build/$STAGENAME"
ls /usr/share/aclocal/libtool.m4

    # Очистка старого мусора, если есть
    rm -rf autom4te.cache config.cache
 
    mkdir -p m4

    # Явно указываем системный путь к макросам libtool
    # Обычно это помогает, когда aclocal внутри контейнера не знает свои пути
    libtoolize --force --copy
    aclocal -I m4 -I /usr/share/aclocal
    autoheader
    automake --add-missing --copy --force-missing
    autoconf

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-docs
        --with-gcc-arch=${CPU_ARCH:-broadwell}
        --disable-multi-os-directory
        --enable-portable-binary #  disable any optimization flags that might result in a binary that only runs on the host architecture
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DFFI_STATIC_BUILD"

    CFLAGS="$CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $static_flags ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # У libffi очень странная привычка ставить хедеры в $(libdir)/libffi-$(version)/include
    # Нам нужно вытащить их в стандартное место
    local FFI_INC_DIR=$(find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "ffi.h" -exec dirname {} \;)
    if [[ -n "$FFI_INC_DIR" ]]; then
        log_info "Moving libffi headers from $FFI_INC_DIR"
        mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include"
        mv -f "$FFI_INC_DIR"/*.h "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"
        rm -rf "${FFI_INC_DIR}"
    fi

    local PC_FILE="$PC_DIR/libffi.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Исправляем путь в pc файле, чтобы он указывал на корень include
        sed -i "s|^includedir=.*|includedir=\${prefix}/include|" "$PC_FILE"
        # Убираем лишние подпапки из Cflags, если они там остались
        sed -i "s|-I\${libdir}/libffi-[^/ ]*/include|-I\${includedir}|g" "$PC_FILE"
        
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
    fi
}
