#!/bin/bash

SCRIPT_REPO="https://github.com/OpenVisualCloud/SVT-JPEG-XS.git"
SCRIPT_COMMIT="b1b227840463d3b74a4da13d8d1f17610697a793"  # Use specific commit hash for reproducible builds

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return -1
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    local cmake_flags=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_C_FLAGS="$CFLAGS"
        -DCMAKE_CXX_FLAGS="$CXXFLAGS"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTING=OFF
        -DBUILD_APPS=OFF
    )

    cmake "${cmake_flags[@]}" ..
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем pkg-config для статической линковки
    # SVT-JPEG-XS генерирует SvtJpegxsEnc.pc и SvtJpegxsDec.pc
    for pc in "${FFBUILD_DESTPREFIX}/lib/pkgconfig/"SvtJpegxs*.pc; do
        [[ -f "$pc" ]] || continue
        # MinGW требует явного указания стандартных библиотек C++ и потоков
        echo "Libs.private: -lstdc++ -lpthread" >> "$pc"
        # Убираем возможные абсолютные пути билда
        sed -i "s|prefix=.*|prefix=$FFBUILD_PREFIX|" "$pc"
    done
}

ffbuild_configure() {
    # Обычно это --enable-libsvtjpegxs
    echo --enable-libsvtjpegxs
}

ffbuild_unconfigure() {
    echo --disable-libsvtjpegxs
}