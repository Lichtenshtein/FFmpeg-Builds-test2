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

    # ручная установка заголовочных файлов
    local inc_dest="${INSTALL_ROOT}/include/librsvg"
    mkdir -p "$inc_dest"

    local src_inc="include/librsvg"
    [ ! -d "$src_inc" ] && [ -d "librsvg-c/include/librsvg" ] && src_inc="librsvg-c/include/librsvg"

    # Генерируем rsvg-version.h из шаблона .in
    if [ -d "$src_inc" ]; then
        cp -f "$src_inc"/rsvg.h "$src_inc"/rsvg-cairo.h "$src_inc"/rsvg-pixbuf.h "$inc_dest/" || true

        # Генерация rsvg-version.h с точной подстановкой под структуру шаблона
        sed -e 's/@LIBRSVG_MAJOR_VERSION@/2/g' \
            -e 's/@LIBRSVG_MINOR_VERSION@/61/g' \
            -e 's/@LIBRSVG_MICRO_VERSION@/4/g' \
            -e 's/@PACKAGE_VERSION@/2.61.4/g' \
            "$src_inc/rsvg-version.h.in" > "$inc_dest/rsvg-version.h"

        # Генерация rsvg-features.h с активацией флагов возможностей
        sed -e 's/@LIBRSVG_HAVE_PIXBUF@/TRUE/g' \
            "$src_inc/rsvg-features.h.in" > "$inc_dest/rsvg-features.h"

        log_info "The librsvg header files were successfully generated and installed."
    else
        log_error "The librsvg source header files were not found in the repository!"
        return 1
    fi

    # Настройка путей в .pc файлах
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*librsvg*.pc" | while read -r PC_FILE; do
            sed -i 's|^Cflags:.*|Cflags: -I${includedir} -I${includedir}/librsvg|' "$PC_FILE"
        done
    fi

    ln -sf librsvg_c.pc "$PC_DIR/librsvg-2.0.pc"
}

ffbuild_configure() {
    echo "--enable-librsvg"
}

ffbuild_unconfigure() {
    echo "--disable-librsvg"
}
