#!/bin/bash
SCRIPT_REPO="https://gitlab.gnome.org/GNOME/pango.git"
SCRIPT_COMMIT="147672f73a7fbfe6a4a89fd436c0b5f4eaa45a81"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
    # echo "git submodule --quiet update --init --recursive --depth=1"
}

ffbuild_dockerbuild() {
    # Отключаем WinRT, который требует отсутствующий заголовок
    # Мы подменяем проверку в meson.build или передаем через CFLAGS
    export CFLAGS="$CFLAGS -D_G_WIN32_WINNT=0x0601 -DG_WIN32_IS_STRICT_MINGW"
    export CXXFLAGS="$CXXFLAGS -D_G_WIN32_WINNT=0x0601 -DG_WIN32_IS_STRICT_MINGW"

    mkdir build && cd build

    meson setup --prefix="$FFBUILD_PREFIX" \
        --cross-file=/cross.meson \
        --default-library=static \
        --buildtype=release \
        --wrap-mode=nodownload \
        -Dintrospection=disabled \
        -Dfontconfig=enabled \
        -Dsysprof=disabled \
        -Dgtk_doc=false \
        ..

    ninja -j$(nproc)  $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install
}
