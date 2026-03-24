#!/bin/bash

SCRIPT_REPO="https://github.com/zdenop/jbigkit.git"
SCRIPT_COMMIT="4690140176ddbc3943d2b794d4b31993d7a509e1"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_PROGRAMS=OFF
        -DBUILD_TOOLS=OFF
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake "${myconf[@]}" .. || return 1
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Исправляем странное именование CMake (liblibjbig.a -> libjbig.a)
    pushd "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib"
    for f in liblibjbig*.a; do
        mv "$f" "${f#lib}" 2>/dev/null || true
    done
    popd

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/jbigkit.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: jbigkit
Description: JBIG1 lossless image compression library
Version: 2.1
Libs: -L\${libdir} -ljbig
Cflags: -I\${includedir}
EOF

}
