#!/bin/bash
export USE_VERS_FINDER=1
SCRIPT_REPO="https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git"
SCRIPT_COMMIT="eadd00804d5f7e5cd8c85d540073198312870776"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf .git Thirdparty"
    if [[ -d ".git" ]]; then
        git add .
    fi
}

ffbuild_dockerbuild() {
    set -e
    mkdir -p "$INSTALL_ROOT"/include
    mv amf/public/include "$INSTALL_ROOT"/include/AMF

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/amf.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: AMF
Description: The Advanced Media Framework (AMF) SDK to access to AMD devices for multimedia processing
Version: ${VER_FULL}
Cflags: -I\${includedir} -I\${includedir}/AMF
EOF
}

ffbuild_configure() {
    echo --enable-amf
}

ffbuild_unconfigure() {
    echo --disable-amf
}
