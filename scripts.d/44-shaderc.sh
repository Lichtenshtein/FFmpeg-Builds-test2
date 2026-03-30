#!/bin/bash

SCRIPT_REPO="https://github.com/google/shaderc.git"
SCRIPT_COMMIT="1d234d34d43cf5ade135803f7777484eaa48e27f"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    # echo "./utils/git-sync-deps || exit $?"
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

        # -DENABLE_GLSLANG_BINARIES=OFF
    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        # -Dglslang_SOURCE_DIR="$FFBUILD_PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF ) \
        -DENABLE_EXCEPTIONS=ON \
        -DGLSLANG_ENABLE_INSTALL=ON \
        -DSHADERC_ENABLE_SHARED_CRT=OFF \
        -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
        -DSHADERC_SKIP_EXAMPLES=ON \
        -DSHADERC_SKIP_TESTS=ON \
        -DSPIRV_SKIP_EXECUTABLES=ON \
        -DSPIRV_TOOLS_BUILD_STATIC=ON \
        -DSPIRV_TOOLS_LIBRARY_TYPE=STATIC .. || return 1

    export DESTDIR="/tmp/staging$FFBUILD_DESTDIR"
    ninja install || return 1

    if [[ $TARGET == win* ]]; then
        rm -r "${DESTDIR}${FFBUILD_PREFIX}"/bin "${DESTDIR}${FFBUILD_PREFIX}"/lib/*.dll.a
    elif [[ $TARGET == linux* ]]; then
        rm -r "${DESTDIR}${FFBUILD_PREFIX}"/bin "${DESTDIR}${FFBUILD_PREFIX}"/lib/*.so*
    else
        echo "Unknown target"
        return 1
    fi

    cp -a "$DESTDIR"/. "$FFBUILD_DESTDIR"
    rm -rf "$DESTDIR"
    unset DESTDIR

    # for some reason, this does not get installed...
    cp libshaderc_util/libshaderc_util.a "$FFBUILD_DESTPREFIX"/lib

    echo "Libs: -lstdc++" >> "$PC_DIR/shaderc_combined.pc"
    echo "Libs: -lstdc++" >> "$PC_DIR/shaderc_static.pc"

    cp "$PC_DIR"/{shaderc_combined,shaderc}.pc

    mkdir ../native_build && cd ../native_build

    unset CC CXX CFLAGS CXXFLAGS LD LDFLAGS AR RANLIB NM DLLTOOL PKG_CONFIG_LIBDIR

    cmake -GNinja \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -Dglslang_SOURCE_DIR="$FFBUILD_PREFIX" \
        -DSHADERC_GLSLANG_DIR="$FFBUILD_SOURCE_DIR/glslang" \
        -DSHADERC_SPIRV_TOOLS_DIR="$FFBUILD_SOURCE_DIR/spirv-tools" \
        -DSHADERC_SPIRV_HEADERS_DIR="$FFBUILD_SOURCE_DIR/spirv-headers" \
        -DENABLE_EXCEPTIONS=ON \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF ) \
        -DGLSLANG_ENABLE_INSTALL=ON \
        -DSHADERC_ENABLE_SHARED_CRT=OFF \
        -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
        -DSHADERC_SKIP_EXAMPLES=ON \
        -DSHADERC_SKIP_TESTS=ON \
        -DSPIRV_SKIP_EXECUTABLES=ON \
        -DSPIRV_TOOLS_BUILD_STATIC=ON \
        -DSPIRV_TOOLS_LIBRARY_TYPE=STATIC .. || return 1

    ninja $NINJA_V -j$(nproc) glslc/glslc || return 1

    cp glslc/glslc /opt/glslc

}

ffbuild_configure() {
    echo --enable-libshaderc
}

ffbuild_unconfigure() {
    echo --disable-libshaderc
}
