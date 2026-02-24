#!/bin/bash

SCRIPT_REPO="https://github.com/vapoursynth/vapoursynth.git"
SCRIPT_COMMIT="42a3bba6f0fffe3a397fa3494aadb7be1e2af8de"

ffbuild_depends() {
    echo zlib
    echo zimg
}

ffbuild_enabled() {
    # Поддерживаем только x86_64
    [[ $TARGET == win64 ]] && return 0
    return 1
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {

    # _python_ver=3.13.11
    # _python_lib=python313
    # _vsver=73
        # create_build_dir
        # declare -A _pc_vars=(
            # [vapoursynth-name]=vapoursynth
            # [vapoursynth-description]='A frameserver for the 21st century'
            # [vapoursynth-cflags]="-DVS_CORE_EXPORTS"

            # [vsscript-name]=vapoursynth-script
            # [vsscript-description]='Library for interfacing VapourSynth with Python'
            # [vsscript-private]="-l$_python_lib"
        # )
        # for _file in vapoursynth vsscript; do
            # gendef - "../$_file.dll" 2>/dev/null |
                # sed -E 's|^_||;s|@[1-9]+$||' > "${_file}.def"
            # do_dlltool "lib${_file}.a" "${_file}.def"
            # [[ -f lib${_file}.a ]] && do_install "lib${_file}.a"
            # printf '%s\n' \
               # "prefix=$LOCALDESTDIR" \
               # 'exec_prefix=${prefix}' \
               # 'libdir=${exec_prefix}/lib' \
               # 'includedir=${prefix}/include/vapoursynth' \
               # "Name: ${_pc_vars[${_file}-name]}" \
               # "Description: ${_pc_vars[${_file}-description]}" \
               # "Version: $_vsver" \
               # "Libs: -L\${libdir} -l${_file}" \
               # "Libs.private: ${_pc_vars[${_file}-private]}" \
               # "Cflags: -I\${includedir} ${_pc_vars[${_file}-cflags]}" \
               # > "${_pc_vars[${_file}-name]}.pc"
        # done

    # Чтобы FFmpeg работал с Vapoursynth, ему нужна библиотека VSScript.
    # Но VSScript требует Python. Мы отключаем модуль Python, но оставляем VSScript 
    # в режиме 'headers only' или минимальной статики, если это позволит Meson.

    # Исправляем баг libtool/linker path для MinGW
    export LT_SYS_LIBRARY_PATH="$FFBUILD_PREFIX/lib"

        # --cross-file="$FFBUILD_CROSS_PREFIX"cross.meson
        # -Dcore=false
        # -Dtests=false

    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file=/cross.meson \
        --buildtype release \
        --default-library static \
        -Denable_x86_asm=true \
        -Denable_vsscript=true \
        -Denable_vspipe=false \
        -Denable_python_module=false \
        || (tail -n 500 build/meson-logs/meson-log.txt && exit 1)

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Исправление pkg-config для статической линковки FFmpeg
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/vapoursynth.pc"
    local VSS_PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/vapoursynth-script.pc"

    if [[ -f "$PC_FILE" ]]; then
        # Убеждаемся, что пути корректны
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        # Добавляем стандартную библиотеку C++, так как VS написан на ней
        sed -i "s|^Libs:.*|Libs: -L\${libdir} -lvapoursynth -lstdc++|" "$PC_FILE"
    fi

    if [[ -f "$VSS_PC_FILE" ]]; then
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$VSS_PC_FILE"
        sed -i "s|^Libs:.*|Libs: -L\${libdir} -lvsscript -lstdc++|" "$VSS_PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-vapoursynth
}

ffbuild_unconfigure() {
    echo --disable-vapoursynth
}

ffbuild_cflags() {
    # Флаг для статической сборки, чтобы избежать __declspec(dllimport)
    echo "-DVAPOURSYNTH_STATIC"
}