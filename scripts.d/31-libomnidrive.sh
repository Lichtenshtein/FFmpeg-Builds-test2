#!/bin/bash

SCRIPT_REPO="https://forgejo.phillippepelzer.me/FiLL/omnidrive.git"
SCRIPT_COMMIT="3a18741afe"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build "${INSTALL_ROOT}/include" "${INSTALL_ROOT}/lib" "$PC_DIR" && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    )

    log_info "Configuring libomnidrive..."

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        ninja omnidrive_shared || return 1
        if [[ -f "libomnidrive.dll" ]]; then
            mkdir -p "$INSTALL_ROOT/bin"
            cp libomnidrive.dll "$INSTALL_ROOT/bin/"
        fi
        if [[ -f "libomnidrive.dll.a" ]]; then
            cp libomnidrive.dll.a "$INSTALL_ROOT/lib/"
        elif [[ -f "libomnidrive.lib" ]]; then
            cp libomnidrive.lib "$INSTALL_ROOT/lib/libomnidrive.dll.a"
        fi
    else
        ninja omnidrive || return 1
        log_info "Copying static library libomnidrive.a to destination..."
        cp libomnidrive.a "$INSTALL_ROOT/lib/"
    fi

    cp ../include/omnidrive.h "${INSTALL_ROOT}/include/"

    log_info "Generating omnidrive.pc for FFmpeg integration..."
    cat <<EOF > "$PC_DIR/omnidrive.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: omnidrive
Description: OmniDrive library with SCSI backend support
Version: 1.0.0
Libs: -L\${libdir} -lomnidrive
Libs.private: ${LIBS}
Cflags: -I\${includedir}
EOF

    log_info "libomnidrive build and integration descriptors successfully finalized."
}

ffbuild_configure() {
    echo --enable-libomnidrive
}

ffbuild_unconfigure() {
    echo --disable-libomnidrive
}
