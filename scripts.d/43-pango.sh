#!/bin/bash
SCRIPT_REPO="https://gitlab.gnome.org/GNOME/pango.git"
SCRIPT_COMMIT="748d1adc10abc917bd27e12ac9e013409c7f58f8"

ffbuild_depends() {
    echo fontconfig
    echo freetype
    echo glib2
    echo cairo
    echo fribidi
    echo harfbuzz
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    # local DEP_LIBS="-Wl,--start-group -lharfbuzz-icu -lharfbuzz-subset -lharfbuzz-cairo -lharfbuzz-vector -lharfbuzz-raster -lharfbuzz -lcairo-gobject -lcairo -lfontconfig -lfreetype -lgio-2.0 -lgthread-2.0 -lglib-2.0 -lfribidi -lbz2 -lbrotlienc -lbrotlidec -lbrotlicommon -lz -lintl -liconv -lcharset -licuin -licuuc -licudt -Wl,--end-group"
    # local WIN_LIBS="-lrpcrt4 -lusp10 -lgdi32 -lmsimg32 -lruntimeobject -ldwrite -ld2d1 -lwindowscodecs -luuid $LIBS -lstdc++"

    local LDFLAGS=$(echo "$LDFLAGS" | sed 's/-lssp//g')

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file="$FFBUILD_MESON_CROSS"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --wrap-mode=nodownload
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Dintrospection=disabled
        -Dfontconfig=enabled
        -Dfreetype=enabled
        -Dsysprof=disabled
        -Ddocumentation=false
        -Dbuild-testsuite=false
        -Dbuild-examples=false
        -Dman-pages=false
    )

    export static_flags=""
    export self_static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DCAIRO_WIN32_STATIC_BUILD -DPANGO_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW -Dpixman_static" && self_static_flags="-DPANGO_STATIC_COMPILATION"

    sed -i "s/error.*does not have the required FontConfig support.*/message('Bypassed cairo-ft check')/" ../meson.build

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags $self_static_flags" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags $self_static_flags" \
        -Dc_link_args="$LDFLAGS ${USELTO} $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS ${USELTO} $DEP_LIBS $WIN_LIBS" || return 1

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        ninja $NINJA_V || return 1
        DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
    else
        # Собираем только статические библиотеки
        ninja pango/libpango-1.0.a \
              pango/libpangocairo-1.0.a \
              pango/libpangoft2-1.0.a \
              pango/libpangowin32-1.0.a || return 1

        # Создаем структуру директорий в DESTDIR
        mkdir -p "$PC_DIR" "$INSTALL_ROOT/include/pango-1.0/pango"

        # Копируем собранные библиотеки вручную
        cp pango/*.a "$INSTALL_ROOT/lib/"

        # Копируем заголовочные файлы
        cp ../pango/*.h "$INSTALL_ROOT/include/pango-1.0/pango/" 2>/dev/null || true
        cp pango/*.h "$INSTALL_ROOT/include/pango-1.0/pango/" 2>/dev/null || true

        # Копируем и правим pkg-config файлы
        cp meson-private/*pango*.pc "$PC_DIR/"
    fi

    for pc in "$PC_DIR"/*pango*.pc; do
        [[ -e "$pc" ]] || continue
        if [[ -n "$self_static_flags" ]]; then
            if ! grep -qF -- "$self_static_flags" "$pc"; then
                sed -i "/^Cflags:/ s/$/ $self_static_flags/" "$pc"
            fi
        fi
    done
}
