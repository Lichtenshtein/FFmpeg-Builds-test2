#!/bin/bash

SCRIPT_REPO="https://github.com/OpenVisualCloud/SVT-JPEG-XS.git"
SCRIPT_COMMIT="HEAD"  # Use specific commit hash for reproducible builds

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    # Create build directory
    mkdir build && cd build

    local cmake_flags=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_C_FLAGS="$CFLAGS"
        -DCMAKE_CXX_FLAGS="$CXXFLAGS"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=OFF
        -DUNIX=OFF
    )

    # Platform-specific configurations
    if [[ $TARGET == win* ]]; then
        cmake_flags+=(
            -DCMAKE_SYSTEM_NAME=Windows
        )
    elif [[ $TARGET == linux* ]]; then
        cmake_flags+=(
            -DCMAKE_SYSTEM_NAME=Linux
        )
    fi

    # Configure with CMake
    cmake "${cmake_flags[@]}" ..
    
    # Build
    make -j$(nproc)
    
    # Install
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Check library names - SVT-JPEG-XS might use different library names
    ls $FFBUILD_DESTPREFIX/lib/libSvt*
    #Check header locations:
    ls $FFBUILD_DESTPREFIX/include/svt-jpegxs/

    echo "=== Installed files ==="
    find "$FFBUILD_DESTDIR" -type f

    # Fix pkg-config file if it exists
    if [[ -f "${FFBUILD_DESTPREFIX}/lib/pkgconfig/SvtJpegxsEnc.pc" ]]; then
        if [[ $TARGET == win* ]]; then
            echo "Libs.private: -lstdc++ -lpthread" >> "${FFBUILD_DESTPREFIX}/lib/pkgconfig/SvtJpegxsEnc.pc"
        else
            echo "Libs.private: -lstdc++ -lpthread -lm" >> "${FFBUILD_DESTPREFIX}/lib/pkgconfig/SvtJpegxsEnc.pc"
        fi
    fi

    if [[ -f "${FFBUILD_DESTPREFIX}/lib/pkgconfig/SvtJpegxsDec.pc" ]]; then
        if [[ $TARGET == win* ]]; then
            echo "Libs.private: -lstdc++ -lpthread" >> "${FFBUILD_DESTPREFIX}/lib/pkgconfig/SvtJpegxsDec.pc"
        else
            echo "Libs.private: -lstdc++ -lpthread -lm" >> "${FFBUILD_DESTPREFIX}/lib/pkgconfig/SvtJpegxsDec.pc"
        fi
    fi
}

ffbuild_configure() {
    echo --enable-libsvtjpegxs
}

ffbuild_unconfigure() {
    echo --disable-libsvtjpegxs
}