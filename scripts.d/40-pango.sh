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

    # Используем наш глобальный PKG_CONFIG_STATIC=1, чтобы собрать зависимости
    local DEP_LIBS=$(pkg-config --libs --static cairo fontconfig freetype2 harfbuzz glib-2.0 fribidi)
    local CFLAGS="$CFLAGS -DPANGO_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW"
    local CXXFLAGS="$CXXFLAGS -DPANGO_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW"
    # Собираем системные либы Windows
    local WIN_LIBS="-lusp10 -lruntimeobject -ldwrite -ld2d1 -lwindowscodecs -lgdi32 -lmsimg32 $LIBS"

    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file=/cross.meson \
        --buildtype=release \
        --default-library=static \
        --wrap-mode=nodownload \
        -Dintrospection=disabled \
        -Dfontconfig=enabled \
        -Dfreetype=enabled \
        -Dsysprof=disabled \
        -Ddocumentation=false \
        -Dbuild-testsuite=false \
        -Dbuild-examples=false \
        -Dman-pages=false \
        -Dc_args="$CFLAGS" \
        -Dcpp_args="$CXXFLAGS" \
        -Dc_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS"

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Патчим ВСЕ сгенерированные .pc файлы Pango
    log_info "Patching Pango .pc files..."
    for pc in pango.pc pangocairo.pc pangoft2.pc pangowin32.pc; do
        local PC_PATH="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/$pc"
        if [[ -f "$PC_PATH" ]]; then
            # Добавляем системные либы в Libs.private
            # И обязательно прокидываем PANGO_STATIC_COMPILATION в Cflags
            sed -i "/^Libs.private:/ s/$/ $WIN_LIBS -lstdc++/" "$PC_PATH"
            sed -i "/^Cflags:/ s/$/ -DPANGO_STATIC_COMPILATION/" "$PC_PATH"
        fi
    done

    # Вызываем отладку зависимостей
    get_deps_list
}

ffbuild_cppflags() {
    echo "-DPANGO_STATIC_COMPILATION"
}
