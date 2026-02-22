#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/glib.git"
SCRIPT_COMMIT="2.82.4" # Стабильная ветка
# SCRIPT_COMMIT="6b11cae1b3bf3e9cff9485481dd1c0f7e806c361"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
    echo "git submodule update --quiet --init --recursive --depth 1"
}

ffbuild_dockerbuild() {

    cat <<EOF > cross_file.txt
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[binaries]
# exe_wrapper = 'wine'
c = '${FFBUILD_TOOLCHAIN}-gcc'
cpp = '${FFBUILD_TOOLCHAIN}-g++'
ar = '${FFBUILD_TOOLCHAIN}-gcc-ar'
pkg-config = 'pkg-config'
strip = '${FFBUILD_TOOLCHAIN}-strip'
windres = '${FFBUILD_TOOLCHAIN}-windres'
nm = '${FFBUILD_TOOLCHAIN}-gcc-nm'
ranlib = '${FFBUILD_TOOLCHAIN}-gcc-ranlib'

[properties]
# growstack = false
# posix_memalign_with_alignment = false
# printf_has_large_precisions = true
# printf_has_ls_format = true
# have_c99_vsnprintf = true
have_c99_snprintf = true
have_c99_vsnprintf = true
va_val_copy = true
int_res_1 = 4
int_res_2 = 8
needs_exe_wrapper = true
# has_function_gettext = true
# has_function_ngettext = true
# has_function_bindtextdomain = true
# exe_wrapper = '/usr/libexec/wine'
# exe_wrapper = '/usr/lib/x86_64-linux-gnu/wine'
# /usr/lib/wine /usr/include/wine
printf_has_glibc_res1 = true
printf_has_glibc_res2 = true

[built-in options]
c_args = ['-I${FFBUILD_PREFIX}/include', '-DGLIB_STATIC_COMPILATION', '-D_WIN32_WINNT=0x0A00', '-DG_WIN32_IS_STRICT_MINGW']
cpp_args = ['-I${FFBUILD_PREFIX}/include', '-DGLIB_STATIC_COMPILATION', '-D_WIN32_WINNT=0x0A00', '-DG_WIN32_IS_STRICT_MINGW']
c_link_args = ['-L${FFBUILD_PREFIX}/lib', '-lintl', '-liconv', '-lffi', '-lpcre2-8']
cpp_link_args = ['-L${FFBUILD_PREFIX}/lib', '-lintl', '-liconv', '-lffi', '-lpcre2-8']
EOF

    # Настройка окружения для Meson
    export PKG_CONFIG_LIBDIR="$FFBUILD_PREFIX/lib/pkgconfig:$FFBUILD_PREFIX/share/pkgconfig"
    unset PKG_CONFIG_PATH

    # Удаляем субпроекты, которые ломают сборку
    rm -rf subprojects/sysprof subprojects/pcre2 subprojects/libffi

    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file cross_file.txt \
        --buildtype release \
        --default-library static \
        --wrap-mode=nodownload \
        -Dtests=false \
        -Dinstalled_tests=false \
        -Dintrospection=disabled \
        -Dlibmount=disabled \
        -Dnls=enabled \
        -Dglib_debug=disabled \
        -Dforce_posix_threads=true \
        -Dman-pages=disabled \
        -Dselinux=disabled \
        -Dsysprof=disabled \
        -Dinternal_pcre=false \
        || (tail -n 500 build/meson-logs/meson-log.txt && exit 1)

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Чистим мусор
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "*.dll.a" -delete || true
    # Фикс .pc файла (обязательно для статической линковки FFmpeg)
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/glib-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Добавляем зависимости, которые Meson часто забывает для static win64
        sed -i 's/^Libs:/Libs: -lws2_32 -lole32 -lshlwapi -luserenv -lsetupapi -liphlpapi -lwinmm -ldnsapi -lruntimeobject/' "$PC_FILE"
        # Убеждаемся, что зависимости тоже вписаны
        sed -i 's/^Requires.private:/Requires.private: libffi, libpcre2-8,/' "$PC_FILE" || true
    fi
}

ffbuild_cflags() {
    echo "-DGLIB_STATIC_COMPILATION"
}

ffbuild_libs() {
    echo "-luserenv -liphlpapi -lintl -liconv -lwinmm -ldnsapi -lruntimeobject -lpthread"
}
