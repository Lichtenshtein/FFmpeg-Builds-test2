#!/bin/bash

# SCRIPT_REPO="https://github.com/drowe67/codec2.git"
# SCRIPT_COMMIT="96e8a19c2487fd83bd981ce570f257aef42618f9"

SCRIPT_REPO3="https://github.com/Alex-Pennington/codec2.git"
SCRIPT_COMMIT3="19571e0a2b42340597fd762803f6eb9d030ee4c5"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf codec2/wav codec2/unittest codec2/doc codec2/build_win"
}

ffbuild_dockerbuild() {
    set -e

    # Compile the codebook generator for the host system (Linux) manually
    gcc $HOST_CFLAGS src/generate_codebook.c -o ./generate_codebook_host -lm
    log_info "The generate_codebook_host utility compiled successfully on Linux."

    # Disable executable file building
    # but LEAVE codebook generation (generate_codebook) and the library itself
    if [ -f "src/CMakeLists.txt" ]; then
        sed -i '/if(CMAKE_CROSSCOMPILING)/,/endif(CMAKE_CROSSCOMPILING)/c\add_executable(generate_codebook IMPORTED)\nset_target_properties(generate_codebook PROPERTIES IMPORTED_LOCATION "'$(pwd)'/generate_codebook_host")' src/CMakeLists.txt
        # Comment out all add_executables except the codebook generator, which is needed to build tables
        sed -i '/add_executable/ { /generate_codebook/! s|^|#| }' src/CMakeLists.txt
        # Comment out absolutely all target_link_libraries, except for the one linked to the codec2 library itself
        sed -i '/target_link_libraries[[:space:]]*([[:space:]]*codec2/! { /target_link_libraries/ s|^|#| }' src/CMakeLists.txt
        # Disabling installation instructions for now non-existent binaries
        sed -i 's|RUNTIME DESTINATION bin||g' src/CMakeLists.txt
        sed -i 's|bundle_gavl_deps||g' src/CMakeLists.txt
    fi

    # Disable the tests and demo folders at the top level
    sed -i 's|add_subdirectory(unittest)|# add_subdirectory(unittest)|g' CMakeLists.txt
    sed -i 's|add_subdirectory(demo)|# add_subdirectory(demo)|g' CMakeLists.txt
    sed -i 's|if(WIN32)|if(FALSE)|g' CMakeLists.txt

    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DUNITTEST=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake "${myconf[@]}" .. || return 1

    # Compile and install it normally via CMake/DESTDIR
    make -j$(nproc) || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Manually generate the correct version.h, since we bypassed the standard src/CMakeLists.txt
    log_info "Generating version.h manually..."
    mkdir -p "$INSTALL_ROOT/include/codec2"
    cat << 'EOF' > "$INSTALL_ROOT/include/codec2/version.h"
#ifndef CODEC2_HAVE_VERSION
#define CODEC2_HAVE_VERSION
#define CODEC2_VERSION_MAJOR 1
#define CODEC2_VERSION_MINOR 2
#define CODEC2_VERSION "${VER_FULL}"
#endif
EOF

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/codec2.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: codec2
Description: A speech codec designed for communications quality speech between 700 and 3200 bit/s
Version: ${VER_FULL}
Libs: -L\${libdir} -lcodec2
Libs.private: -lm
Cflags: -I\${includedir} -I\${includedir}/codec2
EOF

    # Final validation of artifacts before release
    if [[ "${PREFER_SHARED}" != "1" ]]; then
        if [[ -f "$INSTALL_ROOT/lib/libcodec2.a" && -f "$INSTALL_ROOT/include/codec2/version.h" ]]; then
            log_info "${CHECK_MARK} SUCCESS: libcodec2.a and version.h are completely ready."
        else
            log_error "Critical files missing in $INSTALL_ROOT"
            return 1
        fi
    fi
}

ffbuild_configure() {
    echo --enable-libcodec2
}

ffbuild_unconfigure() {
    echo --disable-libcodec2
}
