#!/bin/bash
export USE_VERS_FINDER=1
SCRIPT_REPO="https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git"
SCRIPT_COMMIT="c35f613aea2e5057a688c979e75b1cf24253297e"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf Thirdparty amf/public/samples amf/public/src amf/doc"
    if [[ -d ".git" ]]; then
        git add .
    fi
}

ffbuild_dockerbuild() {
    set -e

    # FFmpeg 8's libavfilter/vsrc_amf.c (built as C) transitively includes these
    # AMF component headers, but the headers ship an unguarded
    #   extern "C"
    #   { ... }
    # block. Wrap each one in #ifdef __cplusplus so C compilation succeeds —
    # the declarations reference C++ namespace types (amf::AMFContext*) and were
    # never C-callable to begin with.
    for h in amf/public/include/components/Ambisonic2SRenderer.h \
             amf/public/include/components/AudioCapture.h \
             amf/public/include/components/ChromaKey.h \
             amf/public/include/components/DisplayCapture.h \
             amf/public/include/components/VideoCapture.h \
             amf/public/include/components/ZCamLiveStream.h; do
        awk '
            /^extern "C"$/ && !in_block { print "#ifdef __cplusplus"; print; in_block = 1; next }
            in_block && /^}$/ { print; print "#endif"; in_block = 0; next }
            { print }
        ' "$h" > "$h.new" && mv "$h.new" "$h"
    done

    mkdir -p "$INSTALL_ROOT"/include
    mv amf/public/include "$INSTALL_ROOT"/include/AMF

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/amf.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: AMF
Description: The Advanced Media Framework SDK to access to AMD devices for multimedia processing
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
