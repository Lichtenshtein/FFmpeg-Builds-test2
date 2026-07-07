#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/libbluray.git"
SCRIPT_COMMIT="4dfb9b0123b006ce5d66592dc8058f61e5c0cdc8"

ffbuild_depends() {
    echo libxml2
    echo freetype
    echo fontconfig
    echo harfbuzz
    echo libudfread
    echo libgpg-error
    echo libgcrypt
    echo libaacs
    echo libbdplus
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Заменяем базовые утилиты работы со строками, чтобы избежать коллизий при статической линковке
    log_info "Patching conflicting string functions in source tree..."
    find . -type f \( -name "*.c" -o -name "*.h" -o -name "meson.build" \) -exec sed -i \
        -e 's/\bstr_dup\b/libbluray_str_dup/g' \
        -e 's/\bstr_printf\b/libbluray_str_printf/g' \
        -e 's/\bstr_print_hex\b/libbluray_str_print_hex/g' {} +

    # Переименование структуры/функции инициализации декодера dec_init
    log_info "Patching dec_init symbol signature..."
    if [[ -f "src/libbluray/disc/dec.c" ]]; then
        sed -i 's/\bdec_init\b/libbluray_dec_init/g' src/libbluray/disc/dec.c
        sed -i 's/\bdec_init\b/libbluray_dec_init/g' src/libbluray/disc/dec.h
        sed -i 's/\bdec_init\b/libbluray_dec_init/g' src/libbluray/disc/disc.c
    fi

    # stop the static library from exporting symbols when linked into a shared lib
    sed -i 's/-DBLURAY_API_EXPORT/-DBLURAY_API_EXPORT_DISABLED/g' src/meson.build

    local PRIVATE_LIBS="-laacs -lbdplus -lgcrypt -lgpg-error"

    mkdir -p build && cd build

    local myconf=(
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        --cross-file="$FFBUILD_MESON_CROSS"
        --prefix="$FFBUILD_PREFIX"
        --libdir="lib"
        --buildtype=release
        -Ddefault_library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Denable_docs=false
        -Denable_tools=false
        -Denable_devtools=false
        -Denable_examples=false
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Dfontconfig=enabled
        -Dfreetype=enabled
        -Dlibxml2=enabled
        -Dlibaacs=enabled
        -Dlibbdplus=enabled
        -Dbdj_jar=auto
    )

    local C_FLAGS="-Ddec_init=libbr_dec_init"

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO:-}${USELTO_C:-} ${C_FLAGS}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO:-}${USELTO_C:-} ${C_FLAGS}" \
        -Dc_link_args="$LDFLAGS ${USELTO:-}${USELTO_L:-}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO:-}${USELTO_L:-}" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    log_info "Deploying BD-J Java runtime assets..."
    find .. -name '*.jar' -exec cp -v {} "${INSTALL_ROOT}/lib/" \; 2>/dev/null || true

    local PC_FILE="$PC_DIR/libbluray.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s|^Cflags:.*|& -I\${includedir}/libbluray|" "$PC_FILE"
        if [[ $TARGET == win64 ]]; then
            if ! grep -qF -- "-lws2_32" "$PC_FILE"; then
                sed -i "/^Libs:/ s/$/ -lws2_32/" "$PC_FILE"
            fi
        fi
        if ! grep -qF -- "-laacs" "$PC_FILE"; then
            echo "Libs.private: -lstdc++ $PRIVATE_LIBS" >> "$PC_FILE"
        fi
    else
        log_error "Critical Error: libbluray.pc was not found in $PC_DIR"
    fi
}

ffbuild_configure() {
    echo --enable-libbluray
}

ffbuild_unconfigure() {
    echo --disable-libbluray
}
