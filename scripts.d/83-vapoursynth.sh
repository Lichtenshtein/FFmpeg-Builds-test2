#!/bin/bash

SCRIPT_REPO="https://github.com/vapoursynth/vapoursynth.git"
SCRIPT_COMMIT="177e8f8a83b44e91af1bc867fafd6bb14dbe8f28"

PY_VER="3.14"
PY_FULL_VER="3.14.1"
PY_LIB="python314"

ffbuild_depends() {
    echo zlib
    echo avisynth
    echo zimg
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .

    # Cleaning before downloading
    echo "git clean -fdx"
    # Windows version of Python (embed); we'll grab the dll and libraries for cross-compilation
    echo "download_file \"https://www.python.org/ftp/python/${PY_FULL_VER}/python-${PY_FULL_VER}-embed-amd64.zip\" \"python_embed.zip\""
    # Headers from the official repository
    echo "download_file \"https://github.com/python/cpython/archive/refs/tags/v${PY_FULL_VER}.zip\" \"python_hdrs.zip\""

    echo "mkdir -p python_win/bin python_win/include temp_hdrs"

    echo "unzip -qo python_embed.zip -d python_win/bin"
    echo "unzip -qo python_hdrs.zip -d temp_hdrs"

    echo "cp -r${OP_V} temp_hdrs/cpython-*/Include/* python_win/include/"
    echo "cp ${OP_VERB} temp_hdrs/cpython-*/PC/pyconfig.h python_win/include/ 2>/dev/null || true"

    echo "rm -rf temp_hdrs python_embed.zip python_hdrs.zip"

    local COMPONENT_NAME="vapoursynth"
    local PATCHES_DIR="${PATCHES_DIR}"
    local CUSTOM_MESON_BUILD="${PATCHES_DIR}/${COMPONENT_NAME}/meson.build"

    if [[ -f "$CUSTOM_MESON_BUILD" ]]; then
        log_info "Replacing meson.build with custom version from patches..."
        echo "cp -rf${OP_V} '$CUSTOM_MESON_BUILD' './meson.build'"
    else
        log_warn "Custom meson.build not found at $CUSTOM_MESON_BUILD. Using default."
    fi
}

ffbuild_dockerbuild() {
    set -e

    local VER_FULL="${VER_FULL:-78}"

    local CUR_DIR=$(pwd)

    # Fix Windows.h registry
    find . -type f \( -name "*.cpp" -o -name "*.h" -o -name "*.c" \) -exec sed -i 's/[Ww]indows.h/windows.h/g' {} +

    local MINGW_INCLUDE=$(find /opt/ct-ng -name "windows.h" -exec dirname {} \; | head -n 1)

    # Generating Python Import Libraries
    ${GENDEF} python_win/bin/${PY_LIB}.dll > ${PY_LIB}.def
    ${DLLTOOL} -d ${PY_LIB}.def -l lib${PY_LIB}.a -D ${PY_LIB}.dll

    # Creating a correct pyconfig.h
    cat <<EOF > python_win/include/pyconfig.h
#ifndef Py_PYCONFIG_H
#define Py_PYCONFIG_H
#define MS_WIN64
#define _WIN64
#define MS_WINDOWS
#define Py_ENABLE_SHARED
#define SIZEOF_VOID_P 8
#define SIZEOF_SIZE_T 8
#define SIZEOF_LONG 4
#define SIZEOF_LONG_LONG 8
#define SIZEOF_WCHAR_T 2
#define WIN32_THREADS 1
#define WITH_THREAD 1
#include <patchlevel.h>
#endif
EOF

    mkdir -p fake_pkgconfig
    cat <<EOF > fake_pkgconfig/python3.pc
prefix=${CUR_DIR}/python_win
libdir=${CUR_DIR}
includedir=\${prefix}/include

Name: python3
Version: ${PY_VER}
Description: Fake Python
Libs: -L\${libdir} -l${PY_LIB}
Cflags: -I\${includedir} -DMS_WIN64 -DMS_WINDOWS
EOF

    ln -sf python3.pc fake_pkgconfig/python-${PY_VER}.pc

    cat <<EOF > python_fix.ini
[binaries]
pkg-config = '${PKG_CONFIG}'
c_ld = '${TARGET_LD}'
cpp_ld = '${TARGET_LD}'

[properties]
pkg_config_libdir = ['${CUR_DIR}/fake_pkgconfig', '${PKG_CONFIG_LIBDIR}']
pkg_config_static = $( [[ "$PREFER_SHARED" == "1" ]] && echo "false" || echo "true" )

[built-in options]
c_args = ['-I${CUR_DIR}/python_win/include', '-DMS_WIN64', '-DMS_WINDOWS']
cpp_args = ['-I${CUR_DIR}/python_win/include', '-DMS_WIN64', '-DMS_WINDOWS']
c_link_args = ['-L${CUR_DIR}', '-l${PY_LIB}']
cpp_link_args = ['-L${CUR_DIR}', '-l${PY_LIB}']
EOF

    # Clearing system paths so Meson doesn't see Linux headers
    export PKG_CONFIG_LIBDIR="${CUR_DIR}/fake_pkgconfig"
    export PKG_CONFIG_PATH=""
    export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=0
    export PKG_CONFIG_ALLOW_SYSTEM_LIBS=0

    FIX_FLAGS="-I${MINGW_INCLUDE} -D_WIN32 -D_WIN64 -DUNICODE -D_UNICODE"

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DVAPOURSYNTH_STATIC"

    mkdir -p build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file="$FFBUILD_MESON_CROSS"
        --cross-file ../python_fix.ini
        --buildtype release
        --default-library $([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dcpp_std=gnu++17 # -std=gnu++20 crashes
        -Dc_std=gnu17
        # -Denable_vsscript=true
        # -Denable_vspipe=false
        -Denable_x86_asm=true
        # -Denable_core=true
        -Dpython.platlibdir="${CUR_DIR}/python_win"
        -Dpython.purelibdir="${CUR_DIR}/python_win"
        # -Denable_python_module=false
        -Dpython.install_env=auto
        -Dpython.bytecompile=0
    )

    unset CPATH
    unset C_INCLUDE_PATH
    unset CPLUS_INCLUDE_PATH

    meson setup "${myconf[@]}" .. \
        -Dc_args="${CFLAGS/-std=gnu17/} $CPPFLAGS ${USELTO}${USELTO_C} $FIX_FLAGS $static_flags" \
        -Dcpp_args="${CXXFLAGS/-std=gnu++20/} $CPPFLAGS ${USELTO}${USELTO_C} $FIX_FLAGS $static_flags" \
        -Dc_link_args="$LDFLAGS ${USELTO}${USELTO_L}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}${USELTO_L}" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Fixing Headers Installation
    log_info "Manually installing headers..."
    mkdir -p "$INSTALL_ROOT/include/vapoursynth"
    cp ${OP_VERB} ../include/VapourSynth4.h "$INSTALL_ROOT/include/vapoursynth/"
    cp ${OP_VERB} ../include/VSScript4.h "$INSTALL_ROOT/include/vapoursynth/"
    cp ${OP_VERB} ../include/VSHelper4.h "$INSTALL_ROOT/include/vapoursynth/" 2>/dev/null || true

    log_info "Copying Python runtime DLLs and ZIP..."
    # Copy the DLL and Python runtime
    mkdir -p "$INSTALL_ROOT/bin"

    # look for the DLL and ZIP in the python_win root, since the embed version does not have a bin folder
    find ../python_win -maxdepth 2 -name "*.dll" -exec cp ${OP_VERB} {} "$INSTALL_ROOT/bin/" \;
    find ../python_win -maxdepth 2 -name "python3*.zip" -exec cp ${OP_VERB} {} "$INSTALL_ROOT/bin/" \;
    find ../python_win -maxdepth 2 -name "*.pyd" -exec cp ${OP_VERB} {} "$INSTALL_ROOT/bin/" \; 2>/dev/null || true

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/vapoursynth.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include/vapoursynth

Name: vapoursynth
Description: A script-based video processing frameserver for the 21st century
Version: ${VER_FULL}
Libs: -L\${libdir} -lvapoursynth
Libs.private: -lstdc++ -lwinmm
Cflags: -I\${includedir} -I\${includedir}/vapoursynth $static_flags
EOF

    cat <<EOF > "$PC_DIR/vapoursynth-script.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include/vapoursynth

Name: vapoursynth-script
Description: Library for interfacing VapourSynth with Python
Version: ${VER_FULL}
Libs: -L\${libdir} -lvsscript
Libs.private: -l${PY_LIB} -lstdc++
Cflags: -I\${includedir} -I\${includedir}/vapoursynth
EOF
}

ffbuild_cflags() {
    echo "$static_flags"
}

ffbuild_libs() {
    echo "-lvsscript"
}

ffbuild_configure() {
    echo --enable-vapoursynth
}

ffbuild_unconfigure() {
    echo --disable-vapoursynth
}
