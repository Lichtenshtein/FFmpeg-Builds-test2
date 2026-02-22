#!/bin/bash
SCRIPT_REPO="https://gitlab.gnome.org/GNOME/pango.git"
SCRIPT_COMMIT="147672f73a7fbfe6a4a89fd436c0b5f4eaa45a81"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
    echo "git submodule --quiet update --init --recursive --depth=1"
}

ffbuild_dockerbuild() {
    # Отключаем WinRT, который требует отсутствующий заголовок
    # Мы подменяем проверку в meson.build или передаем через CFLAGS
    export CFLAGS="$CFLAGS -D_WIN32_WINNT=0x0A00 -DPANGO_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW"
    export CXXFLAGS="$CXXFLAGS -D_WIN32_WINNT=0x0A00 -DPANGO_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW"
    local EXTRA_LDFLAGS="-L${FFBUILD_PREFIX}/lib -lintl -liconv -lusp10 -lshlwapi"

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

    # Линковка Pango в FFmpeg требует Uniscribe
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/pango.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i 's/^Libs:.*/& -lusp10 -lshlwapi -lsetupapi/' "$PC_FILE"
    fi
}
