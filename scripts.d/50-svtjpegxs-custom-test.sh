#!/bin/bash

SCRIPT_REPO="https://github.com/OpenVisualCloud/SVT-JPEG-XS.git"
SCRIPT_COMMIT="HEAD"

ffbuild_enabled() {
    return 1
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # SVT-JPEG-XS uses Build/linux/build.sh
    # need to adapt it for cross-compilation
    
    mkdir -p build && cd build

    # Direct CMake configuration (bypassing their build script)
    CFLAGS="$CFLAGS $CPPFLAGS -mstackrealign -fno-asynchronous-unwind-tables" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -mstackrealign -fno-asynchronous-unwind-tables" \
    LDFLAGS="$LDFLAGS" \
    cmake \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DUNIX=OFF \
        -DBUILD_TESTING=OFF \
        -DBUILD_APPS=OFF \
        .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Check library names - SVT-JPEG-XS might use different library names
    ls $FFBUILD_DESTPREFIX/lib/libSvt*
    #Check header locations:
    ls $FFBUILD_DESTPREFIX/include/svt-jpegxs/

    echo "=== Installed files ==="
    find "$FFBUILD_DESTDIR" -type f

    # Create pkg-config files manually if they don't exist
    if [[ ! -f "${FFBUILD_DESTPREFIX}/lib/pkgconfig/SvtJpegxsEnc.pc" ]]; then
        mkdir -p "${FFBUILD_DESTPREFIX}/lib/pkgconfig"
        
        cat > "${FFBUILD_DESTPREFIX}/lib/pkgconfig/SvtJpegxsEnc.pc" <<EOF
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: SvtJpegxsEnc
Description: SVT JPEG XS Encoder
Version: 0.9
Libs: -L\${libdir} -lSvtJpegxsEnc
Libs.private: -lstdc++ -lpthread -lm
Cflags: -I\${includedir}
EOF

        cat > "${FFBUILD_DESTPREFIX}/lib/pkgconfig/SvtJpegxsDec.pc" <<EOF
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: SvtJpegxsDec
Description: SVT JPEG XS Decoder
Version: 0.9
Libs: -L\${libdir} -lSvtJpegxsDec
Libs.private: -lstdc++ -lpthread -lm
Cflags: -I\${includedir}
EOF
    fi

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libsvtjpegxs
}

ffbuild_unconfigure() {
    echo --disable-libsvtjpegxs
}