#!/bin/bash
export USE_VERS_FINDER=1
SCRIPT_REPO="https://codeberg.org/soundtouch/soundtouch.git"
SCRIPT_COMMIT="f738b1132ec1fd56efc90367898244cf52d9e6a5"

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
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DINTEGER_SAMPLES=OFF # FFmpeg/Avisynth предпочитают Float
        -DSOUNDSTRETCH=OFF    # Утилита не нужна, только библиотека
        -DSOUNDTOUCH_DLL=OFF  # Нам нужна основная либа, а не C-wrapper DLL
        -DNEON=OFF
    )

    if [[ "$USE_OPENMP" == "1" ]]; then
        myconf+=( -DOPENMP=ON )
    else
        myconf+=( -DOPENMP=OFF )
    fi

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/soundtouch.pc"
    if [[ ! -f "$PC_FILE" ]]; then
        mkdir -p "$PC_DIR"
        cat <<EOF > "$PC_FILE"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: SoundTouch
Description: Audio Processing Library
Version: ${VER_FULL}
Libs: -L\${libdir} -lSoundTouch
Libs.private: -lstdc++ -lm
Cflags: -I\${includedir}/soundtouch -DSOUNDTOUCH_FLOAT_SAMPLES
EOF
    fi
}
