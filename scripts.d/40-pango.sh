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
    # echo "git submodule --quiet update --init --recursive --depth=1"
}

ffbuild_dockerbuild() {

    export CFLAGS="$CFLAGS -DCAIRO_WIN32_STATIC_BUILD -D_WIN32_WINNT=0x0A00 -DPANGO_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW -DHARFBUZZ_STATIC"
    export CXXFLAGS="$CXXFLAGS -DCAIRO_WIN32_STATIC_BUILD -D_WIN32_WINNT=0x0A00 -DPANGO_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW -DHARFBUZZ_STATIC"

    # Полный список либ для прохождения проверок Meson
    # Порядок ВАЖЕН: pango -> pangocairo -> cairo -> fontconfig -> freetype -> pixman ...
    local EXTRA_LDFLAGS="-L${FFBUILD_PREFIX}/lib -lcairo -lfontconfig -lfreetype -lharfbuzz -lpixman-1 -lpng -lz -lbz2 -lbrotlidec -lbrotlicommon -lxml2 -llzma -liconv -lintl -lbcrypt -lws2_32 -lusp10 -lshlwapi -ldwrite -ld2d1 -lwindowscodecs -lgdi32 -lmsimg32 -lole32 -luser32 -lsetupapi -lruntimeobject -lstdc++"

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
        -Dc_link_args="$EXTRA_LDFLAGS" \
        -Dcpp_link_args="$EXTRA_LDFLAGS" \
        || (tail -n 100 build/meson-logs/meson-log.txt && exit 1)

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Фикс .pc файла для FFmpeg
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/pango.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Добавляем всё, что нужно для финальной линковки FFmpeg
        sed -i 's/^Libs:.*/& -lusp10 -lshlwapi -lsetupapi -lruntimeobject -ldwrite -lgdi32 -lstdc++/' "$PC_FILE"
    fi
}
