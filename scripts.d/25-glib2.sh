#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/glib.git"
SCRIPT_COMMIT="6b11cae1b3bf3e9cff9485481dd1c0f7e806c361"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
    echo "git submodule update --quiet --init --recursive --depth 1"
}

ffbuild_dockerbuild() {
    pkg-config --cflags --libs intl
    # инициализация подмодуля gvdb
    if ! git submodule update --init --recursive; then
        echo "Submodule update failed, downloading GVDB manually..."
        rm -rf subprojects/gvdb
        git clone --depth 1 https://github.com/GNOME/gvdb.git subprojects/gvdb
    fi

    cat <<EOF > cross_file.txt
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[binaries]
c = '${FFBUILD_TOOLCHAIN}-gcc'
cpp = '${FFBUILD_TOOLCHAIN}-g++'
ar = '${FFBUILD_TOOLCHAIN}-gcc-ar'
pkg-config = 'pkg-config'
strip = '${FFBUILD_TOOLCHAIN}-strip'
windres = '${FFBUILD_TOOLCHAIN}-windres'
nm = '${FFBUILD_TOOLCHAIN}-gcc-nm'
ranlib = '${FFBUILD_TOOLCHAIN}-gcc-ranlib'

[properties]
posix_memalign_with_alignment = false
growstack = false
have_c99_snprintf = true
have_c99_vsnprintf = true
va_val_copy = true
growing_stack = false
needs_exe_wrapper = true
#has_function_gettext = true
#has_function_ngettext = true
#has_function_bindtextdomain = true

[built-in options]
c_args = ['-I${FFBUILD_PREFIX}/include']
cpp_args = []
c_link_args = ['-L${FFBUILD_PREFIX}/lib', '-lintl', '-liconv']
cpp_link_args = ['-L${FFBUILD_PREFIX}/lib', '-lintl', '-liconv']
EOF

    # Настройка окружения для Meson
    export PKG_CONFIG_LIBDIR="$FFBUILD_PREFIX/lib/pkgconfig:$FFBUILD_PREFIX/share/pkgconfig"
    unset PKG_CONFIG_PATH 
    export CFLAGS="$CFLAGS -D_G_WIN32_WINNT=0x0A00 -DGLIB_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW"
    export CXXFLAGS="$CXXFLAGS -D_G_WIN32_WINNT=0x0A00 -DGLIB_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW"

    # Удаляем субпроекты, которые ломают сборку
    rm -rf subprojects/sysprof subprojects/pcre2 subprojects/libffi

    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file cross_file.txt \
        --buildtype release \
        --default-library static \
        --wrap-mode=nodownload \
        -Dnls=disabled \
        -Dtests=false \
        -Dintrospection=disabled \
        -Dwin32_notifications=disabled \
        -Dlibmount=disabled \
        -Dglib_debug=disabled \
        -Dgio_module_dir="$FFBUILD_PREFIX/lib/gio/modules"

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Чистим мусор
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "*.dll.a" -delete || true
    # Фикс .pc файла (обязательно для статической линковки FFmpeg)
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/glib-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Добавляем зависимости, которые Meson часто забывает для static win64
        sed -i 's/^Libs:/Libs: -lws2_32 -lole32 -lshlwapi -luserenv -lsetupapi -liphlpapi /' "$PC_FILE"
    fi
}

ffbuild_configure() {
    # Для FFmpeg важно знать, что glib статическая
    echo "--enable-libglib";
}

ffbuild_cflags() {
    echo "-DGLIB_STATIC_COMPILATION"
}

ffbuild_libs() {
    echo "-luserenv -liphlpapi -lintl -liconv -lpthread"
}
