#!/bin/bash
export USE_VERS_FINDER=1
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

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_POLICY_DEFAULT_CMP0069=NEW
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_PROGRAMS=OFF
        -DBUILD_TOOLS=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Исправляем странное именование CMake (liblibjbig.a -> libjbig.a)
    pushd "$INSTALL_ROOT/lib"
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
Description: JBIG1 lossless highly effective image data compression library
Version: ${VER_FULL}
Libs: -L\${libdir} -ljbig
Cflags: -I\${includedir}
EOF
}
