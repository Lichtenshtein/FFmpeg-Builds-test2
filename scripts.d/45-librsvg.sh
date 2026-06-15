#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/librsvg.git"
SCRIPT_COMMIT="f7976944494b49518604cc03c36b7341db939010"

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
    echo "rm -rf \
rsvg/tests/fixtures \
rsvg/tests/resources"
}

ffbuild_dockerbuild() {
    set -e

    export SKIP_POST_STRIP=1

    export CARGO_HOME="/opt/cargo"
    export RUSTUP_HOME="/opt/rustup"
    export PKG_CONFIG_ALLOW_CROSS=1
    export RUSTFLAGS="${RUSTFLAGS}"

    # Создаем директорию сборки
    mkdir -p build

    local myconf=(
        --cross-file="$FFBUILD_MESON_CROSS"
        --prefix="$FFBUILD_PREFIX"
        --libdir="lib"
        --buildtype=release
        # -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        # ОТКЛЮЧАЕМ виновников падения кросс-компиляции
        -Dpixbuf=disabled
        -Dpixbuf-loader=disabled
        -Dintrospection=disabled
        -Dvala=disabled
        -Ddocs=disabled
        -Dtests=false
        # ВКЛЮЧАЕМ фичи:
        -Davif=enabled
        -Drsvg-convert=disabled
        # Передаем триплет кросс-компиляции Rust для Meson
        -Dtriplet="${FFBUILD_RUST_TARGET}"
    )

    meson setup "${myconf[@]}" \
        -Dc_args="$CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" \
        . build || return 1

    ninja -C build $NINJA_V || return 1

    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install || return 1

    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*librsvg*.pc" | while read -r PC_FILE; do
            log_info "${SEARCH_MARK} Fixing Meson-generated paths in $PC_FILE..."
            sed -i 's|^Cflags:.*|Cflags: -I${includedir}/librsvg-2.0|' "$PC_FILE"
            # Очищаем Requires.private от "голых" версий (1.3.0, 20.0.14 и т.д.)
            sed -i 's|^Requires.private:.*|Requires.private: cairo-gobject cairo-png dav1d freetype2 harfbuzz libxml-2.0 pangocairo pangoft2 gmodule-2.0 glib-2.0 gio-2.0|' "$PC_FILE"
        done
        if [ -f "$PC_DIR/librsvg_c.pc" ] && [ ! -f "$PC_DIR/librsvg-2.0.pc" ]; then
            ln -sf librsvg_c.pc "$PC_DIR/librsvg-2.0.pc"
        fi
    fi
}

ffbuild_configure() {
    echo "--enable-librsvg"
}

ffbuild_unconfigure() {
    echo "--disable-librsvg"
}
