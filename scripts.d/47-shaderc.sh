#!/bin/bash

SCRIPT_REPO="https://github.com/google/shaderc.git"
SCRIPT_COMMIT="1d234d34d43cf5ade135803f7777484eaa48e27f"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "./utils/git-sync-deps || exit $?"
}

ffbuild_dockerbuild() {
    set -e
    apply_patches

    mkdir build && cd build

        # -DENABLE_EXCEPTIONS=ON 
        # -DENABLE_GLSLANG_BINARIES=OFF
    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DSHADERC_SKIP_TESTS=ON \
        -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
        -DSHADERC_SKIP_EXAMPLES=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DSHADERC_ENABLE_SHARED_CRT=OFF \
        -DSPIRV_SKIP_EXECUTABLES=ON \
        -DSPIRV_TOOLS_BUILD_STATIC=ON \
        -DSPIRV_TOOLS_LIBRARY_TYPE=STATIC \
        -DGLSLANG_ENABLE_INSTALL=ON .. || return 1

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
        -DCMAKE_BUILD_TYPE=Release \
        -DSHADERC_SKIP_TESTS=ON \
        -DSHADERC_SKIP_EXAMPLES=ON \
        -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
        -DENABLE_EXCEPTIONS=ON \
        -DSPIRV_TOOLS_BUILD_STATIC=ON \
        -DBUILD_SHARED_LIBS=OFF .. || return 1

    ninja $NINJA_V -j$(nproc) glslc/glslc || return 1

    cp glslc/glslc /opt/glslc

    patch_pc_files
    clean_la_files
    get_deps_list
}

ffbuild_configure() {
    echo --enable-libshaderc
}

ffbuild_unconfigure() {
    echo --disable-libshaderc
}
