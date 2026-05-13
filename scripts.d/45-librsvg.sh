#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/librsvg.git"
SCRIPT_COMMIT="28b37154cddfda8a0782ee684f34a18964384b41"

ffbuild_depends() {
    echo zlib
    echo xz
    echo bzlib
    echo libxml2
    echo glib2
    echo brotli
    echo cairo
    echo pango
    echo dav1d
    echo avif
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    export SKIP_POST_STRIP=1

    local DEP_LIBS="-lpangocairo-1.0 -lpangowin32-1.0 -lpangoft2-1.0 -lpango-1.0 -lgio-2.0 -lgthread-2.0 -lglib-2.0 -ldav1d -lxml2 -lintl -liconv -lcharset"
    local WIN_LIBS="-luserenv -lusp10 -lruntimeobject -lntdll -lmsimg32 -lgdi32"

    # Настройки для Cargo (Rust кросс-компиляция)
    export CARGO_HOME="/opt/cargo"
    export RUSTUP_HOME="/opt/rustup"
    export PKG_CONFIG_ALLOW_CROSS=1

    local RF="-L native=$FFBUILD_PREFIX/lib -C linker=${FFBUILD_TOOLCHAIN}-gcc -C ar=${FFBUILD_TOOLCHAIN}-gcc-ar"

    local myconf=(
        --release
        --target="${FFBUILD_RUST_TARGET}"
        --prefix="$FFBUILD_PREFIX"
        --destdir="$FFBUILD_DESTDIR"
        --library-type=$([ "${PREFER_SHARED}" == "1" ] && echo cdylib || echo staticlib)
        --features="avif"
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$DEP_LIBS $WIN_LIBS $LIBS" \
    RUSTFLAGS="${RUSTFLAGS} ${RF}" \
    cargo cinstall -p librsvg-c $CARGO_V "${myconf[@]}" || return 1

    # Исправление .pc файла. 
    # librsvg-2.0.pc после сборки часто не содержит Cairo/Pango в Requires.private
    # local PC_FILE="$PC_DIR/librsvg-2.0.pc"
    # if [[ -f "$PC_FILE" ]]; then
        # if grep -q "^Libs.private:" "$PC_FILE"; then
            # sed -i "s|^Libs.private:.*|Libs.private: $DEP_LIBS $WIN_LIBS|" "$PC_FILE"
        # else
            # sed -i "/^Libs:/ a Libs.private: $DEP_LIBS $WIN_LIBS" "$PC_FILE"
        # fi
    # fi

    for pc in "$PC_DIR"/librsvg*.pc; do
        [[ -e "$pc" ]] || continue
        sed -i 's/-lwinapi_kernel32//g'
    done

    ln -sf librsvg_c.pc "$PC_DIR/librsvg-2.0.pc"
}

ffbuild_configure() {
    echo "--enable-librsvg"
}

ffbuild_unconfigure() {
    echo "--disable-librsvg"
}
