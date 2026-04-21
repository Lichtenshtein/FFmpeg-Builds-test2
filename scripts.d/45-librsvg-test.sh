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
    echo freetype2
    echo avif
}

ffbuild_enabled() {
    return 1
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    export SKIP_POST_STRIP=1

    mkdir -p build && cd build

    # Настройки для Cargo (Rust кросс-компиляция)
    export CARGO_HOME="/opt/cargo"
    export RUSTUP_HOME="/opt/rustup"
    export PKG_CONFIG_ALLOW_CROSS=1

    local RF="-L native=$FFBUILD_PREFIX/lib -C linker=${FFBUILD_TOOLCHAIN}-gcc -C ar=${FFBUILD_TOOLCHAIN}-gcc-ar"

    export RUSTFLAGS="${RUSTFLAGS} ${RF}"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file="$FFBUILD_MESON_CROSS"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --wrap-mode=nodownload
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dintrospection=disabled
        -Dpixbuf=disabled
        -Dpixbuf-loader=disabled
        -Dvala=disabled
        -Ddocs=disabled
        -Dtests=false
        -Drsvg-convert=disabled
        -Davif=enabled
        -Dtriplet="$FFBUILD_RUST_TARGET"
    )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # librsvg-2.0.pc после сборки часто не содержит Cairo/Pango в Requires.private
    # local PC_FILE="$PC_DIR/librsvg-2.0.pc"
    # if [[ -f "$PC_FILE" ]]; then
        # # Librsvg (Rust) генерирует огромную статическую либу, которой нужны ВСЕ системные либы Windows
        # sed -i 's/^Libs:.*/& -lpangocairo-1.0 -lpangowin32-1.0 -lpangoft2-1.0 -lpango-1.0 -lcairo-gobject -lcairo -lgio-2.0 -lgthread-2.0 -lglib-2.0 -ldav1d -lxml2 -lintl -liconv -lcharset -luserenv -lusp10 -lruntimeobject -lntdll -lmsimg32 -lgdi32 -lstdc++/' "$PC_FILE"
    # fi
}

ffbuild_configure() {
    echo "--enable-librsvg"
}

ffbuild_unconfigure() {
    echo "--disable-librsvg"
}
