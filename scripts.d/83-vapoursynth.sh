#!/bin/bash
export USE_VERS_FINDER=1
SCRIPT_REPO="https://github.com/vapoursynth/vapoursynth.git"
SCRIPT_COMMIT="33769c5401c63a68b92212430b53abb058bc5f83"

PY_VER="3.14"
PY_FULL_VER="3.14.1"
PY_LIB="python314" # Без точки для линковки

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

    # Очистка перед скачиванием
    echo "git clean -fdx"
    # Windows-версия Python (embed); забраем dll и либы для кросс-компиляции
    echo "download_file \"https://www.python.org/ftp/python/${PY_FULL_VER}/python-${PY_FULL_VER}-embed-amd64.zip\" \"python_embed.zip\""
    # Хедеры из официального репозитория
    echo "download_file \"https://github.com/python/cpython/archive/refs/tags/v${PY_FULL_VER}.zip\" \"python_hdrs.zip\""

    echo "mkdir -p python_win/bin python_win/include temp_hdrs"

    echo "unzip -qo python_embed.zip -d python_win/bin"
    echo "unzip -qo python_hdrs.zip -d temp_hdrs"

    echo "cp -r${OP_V} temp_hdrs/cpython-*/Include/* python_win/include/"
    echo "cp ${OP_VERB} temp_hdrs/cpython-*/PC/pyconfig.h python_win/include/ 2>/dev/null || true"

    echo "rm -rf temp_hdrs python_embed.zip python_hdrs.zip"
}

ffbuild_dockerbuild() {
    set -e

    local VER_FULL="${VER_FULL:-77}"

    cat << EOF > meson.build
project('VapourSynth', 'c', 'cpp',
    default_options: ['buildtype=release', 'b_lto=true', 'b_ndebug=if-release', 'c_std=c99', 'cpp_std=c++17'],
    license: 'LGPL-2.1-or-later',
    license_files: 'COPYING.LESSER',
    meson_version: '>=1.3.0',
    version: '${VER_FULL}',
)

enable_guard_pattern = get_option('enable_guard_pattern')
enable_x86_asm = get_option('enable_x86_asm')

cxx = meson.get_compiler('cpp')

if cxx.get_argument_syntax() == 'gcc'
    avx2_args = '-march=x86-64-v3'
elif cxx.get_id() == 'clang-cl'
    avx2_args = '/clang:-march=x86-64-v3'
else
    avx2_args = '/arch:AVX2'
endif

host_system = host_machine.system()
is_win = host_system in ['cygwin', 'windows']

if is_win
    dl_dep = dependency('', required: false)
    libp2p_dep = dependency('libp2p', static: true, required: false)
else
    dl_dep = dependency('dl')
endif

if not host_machine.cpu_family().startswith('x86')
    enable_x86_asm = false
endif

incdir = include_directories('include')

# We don't look for a Python installation via import('python'), since we're passing the headers manually.
# But we do need a dependency for linking vsscript.

py_dep = dependency('python3', method: 'pkg-config')

vs_current_release = '${VER_FULL}' 

add_project_arguments(
    cxx.get_supported_arguments(
        '-D_CRT_SECURE_NO_WARNINGS',
        '-DNOMINMAX',
        '-DVS_CURRENT_RELEASE=@0@'.format(vs_current_release),
        '-DVS_GRAPH_API',
        '-DVS_USE_LATEST_API',
        '-DVSSCRIPT_USE_LATEST_API',
        '-Wno-ignored-attributes',
    ),
    language: ['c', 'cpp'],
)

if is_win
    add_project_arguments('-DVS_TARGET_OS_WINDOWS', '-D_UNICODE', '-DUNICODE', language: ['c', 'cpp'])
elif host_system == 'darwin'
    add_project_arguments('-DVS_TARGET_OS_DARWIN', language: ['c', 'cpp'])
elif host_system in ['dragonfly', 'freebsd', 'gnu', 'linux', 'netbsd', 'openbsd']
    add_project_arguments('-DVS_TARGET_OS_LINUX', language: ['c', 'cpp'])
endif

if enable_guard_pattern
    add_project_arguments('-DVS_FRAME_GUARD', language: ['c', 'cpp'])
endif

deps = [
    dl_dep,
    dependency('threads'),
    dependency('zimg', static: true, version: '>=3.0.5'),
]

libs = []

if enable_x86_asm
    add_project_arguments('-DVS_TARGET_CPU_X86', language: ['c', 'cpp'])

    libs += static_library('core_sse2',
        files(
            'src/core/expr/jitcompiler_x86.cpp',
            'src/core/kernel/x86/average_sse2.c',
            'src/core/kernel/x86/convolution_sse2.cpp',
            'src/core/kernel/x86/generic_sse2.cpp',
            'src/core/kernel/x86/merge_sse2.c',
            'src/core/kernel/x86/planestats_sse2.c',
            'src/core/kernel/x86/transpose_sse2.c',
        ),
        gnu_symbol_visibility: 'hidden',
        include_directories: incdir,
    )

    libs += static_library('core_avx2',
        files(
            'src/core/kernel/x86/convolution_avx2.cpp',
            'src/core/kernel/x86/generic_avx2.cpp',
            'src/core/kernel/x86/merge_avx2.c',
            'src/core/kernel/x86/planestats_avx2.c',
        ),
        c_args: avx2_args,
        cpp_args: avx2_args,
        gnu_symbol_visibility: 'hidden',
        include_directories: incdir,
    )
endif

libvapoursynth = library('vapoursynth',
    files(
        'src/core/expr/expr.cpp',
        'src/core/expr/jitcompiler.cpp',
        'src/core/kernel/average.cpp',
        'src/core/kernel/cpulevel.cpp',
        'src/core/kernel/generic.cpp',
        'src/core/kernel/merge.c',
        'src/core/kernel/planestats.c',
        'src/core/kernel/transpose.c',
        'src/core/audiofilters.cpp',
        'src/core/averageframesfilter.cpp',
        'src/core/boxblurfilter.cpp',
        'src/core/cpufeatures.cpp',
        'src/core/exprfilter.cpp',
        'src/core/genericfilters.cpp',
        'src/core/lutfilters.cpp',
        'src/core/memoryuse.cpp',
        'src/core/mergefilters.cpp',
        'src/core/reorderfilters.cpp',
        'src/core/simplefilters.cpp',
        'src/core/textfilter.cpp',
        'src/core/vsapi.cpp',
        'src/core/vscore.cpp',
        'src/core/vslog.cpp',
        'src/core/vsresize.cpp',
        'src/core/vsthreadpool.cpp',
    ),
    c_args: '-DVS_CORE_EXPORTS',
    cpp_args: '-DVS_CORE_EXPORTS',
    dependencies: deps,
    gnu_symbol_visibility: 'hidden',
    include_directories: incdir,
    install: true,
    link_with: libs,
)

libvsscript = library('vsscript',
    files('src/vsscript/vsscript.cpp'),
    cpp_args: ['-DPy_NO_LINK_LIB', '-DVS_CORE_EXPORTS'],
    dependencies: [dl_dep, py_dep],
    gnu_symbol_visibility: 'hidden',
    include_directories: incdir,
    install: true,
)

libdir = get_option('libdir')
includedir = get_option('includedir')

pc_data = configuration_data()
pc_data.set('version', meson.project_version())
pc_data.set('prefix', get_option('prefix'))
pc_data.set('libdir', get_option('prefix') / libdir)
pc_data.set('includedir', get_option('prefix') / includedir)

configure_file(
    configuration: pc_data,
    input: 'vapoursynth.pc.in',
    install: true,
    install_dir: libdir / 'pkgconfig',
    output: 'vapoursynth.pc',
)
EOF

    local CUR_DIR=$(pwd)

    # Фикс регистра для Windows.h (Критично для сборки Core)
    find . -type f \( -name "*.cpp" -o -name "*.h" -o -name "*.c" \) -exec sed -i 's/[Ww]indows.h/windows.h/g' {} +

    local MINGW_INCLUDE=$(find /opt/ct-ng -name "windows.h" -exec dirname {} \; | head -n 1)

    # Генерация библиотек импорта Python
    ${FFBUILD_CROSS_PREFIX}gendef python_win/bin/${PY_LIB}.dll > ${PY_LIB}.def
    ${FFBUILD_CROSS_PREFIX}dlltool -d ${PY_LIB}.def -l lib${PY_LIB}.a -D ${PY_LIB}.dll

    # Создание правильного pyconfig.h
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
pkg-config = 'pkgconf'

[properties]
pkg_config_libdir = ['${CUR_DIR}/fake_pkgconfig', '/opt/ffbuild/lib/pkgconfig', '/opt/ffbuild/share/pkgconfig']
pkg_config_static = true

[built-in options]
c_args = ['-I${CUR_DIR}/python_win/include', '-DMS_WIN64', '-DMS_WINDOWS']
cpp_args = ['-I${CUR_DIR}/python_win/include', '-DMS_WIN64', '-DMS_WINDOWS']
c_link_args = ['-L${CUR_DIR}', '-l${PY_LIB}']
cpp_link_args = ['-L${CUR_DIR}', '-l${PY_LIB}']
EOF

    # Очищаем системные пути, чтобы Meson не видел Linux-заголовки
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

    # Исправляем установку заголовков (Headers)
    log_info "Manually installing headers..."
    mkdir -p "$INSTALL_ROOT/include/vapoursynth"
    cp ${OP_VERB} ../include/VapourSynth4.h "$INSTALL_ROOT/include/vapoursynth/"
    cp ${OP_VERB} ../include/VSScript4.h "$INSTALL_ROOT/include/vapoursynth/"
    cp ${OP_VERB} ../include/VSHelper4.h "$INSTALL_ROOT/include/vapoursynth/" 2>/dev/null || true

    log_info "Copying Python runtime DLLs and ZIP..."
    # Копируем DLL и рантайм Python
    mkdir -p "$INSTALL_ROOT/bin"

    # Ищем DLL и ZIP в корне python_win, так как в embed-версии нет папки bin
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
