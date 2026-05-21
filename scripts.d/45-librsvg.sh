#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/librsvg.git"
SCRIPT_COMMIT="c3db18133ba775d55a0f9c6c49ec16ac235a7d8a"

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
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
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

    meson setup "${myconf[@]}" build . \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dc_link_args="$LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}" || return 1

    ninja -C build $NINJA_V || return 1

    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install || return 1

    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*librsvg*.pc" | while read -r PC_FILE; do
            log_info "${SEARCH_MARK} Fixing Meson-generated paths in $PC_FILE..."
            sed -i 's|^Cflags:.*|Cflags: -I${includedir}/librsvg-2.0|' "$PC_FILE"
        done
        if [ -f "$PC_DIR/librsvg_c.pc" ] && [ ! -f "$PC_DIR/librsvg-2.0.pc" ]; then
            ln -sf librsvg_c.pc "$PC_DIR/librsvg-2.0.pc"
        fi
    fi

    log_info "${CHECK_MARK} Librsvg successfully cross-compiled via Meson."
}


ffbuild_configure() {
    echo "--enable-librsvg"
}

ffbuild_unconfigure() {
    echo "--disable-librsvg"
}
