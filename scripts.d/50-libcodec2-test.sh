#!/bin/bash

SCRIPT_REPO="https://github.com/arancormonk/codec2.git"
SCRIPT_COMMIT="6a787012632b8941aa24a4ea781440b61de40f57"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    # Это предотвратит запуск и копирование generate_codebook
    sed -i 's/add_subdirectory(codec2_native)//g' src/CMakeLists.txt
    sed -i 's/add_dependencies(codec2 codec2_native)//g' src/CMakeLists.txt
    mkdir build && cd build

    local mycmake=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_C_FLAGS="$CFLAGS"
        -DCMAKE_CXX_FLAGS="$CXXFLAGS"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
        -DBUILD_SHARED_LIBS=OFF
        -DGENERATE_CODEBOOKS=OFF
        -DUNITTEST=OFF
        -DINSTALL_EXAMPLES=OFF
    )

    cmake "${mycmake[@]}" ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libcodec2
}

ffbuild_unconfigure() {
    echo --disable-libcodec2
}
