#!/bin/bash
SCRIPT_REPO="https://github.com/GNOME/glib.git"
SCRIPT_COMMIT="6b11cae1b3bf3e9cff9485481dd1c0f7e806c361"
# SCRIPT_COMMIT="2.80.0"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    # Изменить 'v1' на 'v2', чтобы сбросить кэш загрузки
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" . && echo 'v5-meson-upgrade'"
}

ffbuild_dockerbuild() {
    # ОБНОВЛЯЕМ MESON до последней версии
    pip3 install --break-system-packages --upgrade meson

    # Удаляем только pcre2 из субпроектов, чтобы заставить использовать наш билд
    # Но НЕ трогаем gvdb
    rm -rf subprojects/pcre2*

    meson subprojects download

    # Подготавливаем строки аргументов заранее
    # Превращаем "-O3 -march=broadwell" в "'-O3', '-march=broadwell'"
    MESON_C_ARGS=$(echo $CFLAGS | xargs -n1 | sed "s/.*/'&'/" | paste -sd, -)
    MESON_CXX_ARGS=$(echo $CXXFLAGS | xargs -n1 | sed "s/.*/'&'/" | paste -sd, -)
    MESON_L_ARGS=$(echo $LDFLAGS | xargs -n1 | sed "s/.*/'&'/" | paste -sd, -)

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
# Эти параметры критичны для кросс-компиляции GLib 2.80+
growing_stack = false
have_c99_snprintf = true
have_c99_vsnprintf = true
va_val_copy = true

[built-in options]
c_args = [$MESON_C_ARGS]
cpp_args = [$MESON_CXX_ARGS]
c_link_args = [$MESON_L_ARGS]
cpp_link_args = [$MESON_L_ARGS]
EOF

    # Проверка созданного файла в логах (для отладки)
    echo "--- CROSS FILE START ---"
    cat cross_file.txt
    echo "--- CROSS FILE END ---"

    export CPATH="$FFBUILD_PREFIX/include"
    export LIBRARY_PATH="$FFBUILD_PREFIX/lib"
    export PKG_CONFIG_LIBDIR="$FFBUILD_PREFIX/lib/pkgconfig"
    # перед meson setup, чтобы он увидел pcre2
    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig"

#         --wrap-mode nodownload
    # Используем -Dwrap_mode=nofallback чтобы не скачивал ничего лишнего
    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file cross_file.txt \
        --buildtype release \
        --default-library static \
        -Dtests=false \
        -Dintrospection=disabled \
        -Dlibmount=disabled \
        -Dnls=disabled

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Очистка префикса (удаляем импортные библиотеки DLL, если они создались)
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "*.dll.a" -delete
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "*.a.p" -rmdir 2>/dev/null || true
}

ffbuild_configure() {
    # Для FFmpeg важно знать, что glib статическая
    echo "--enable-libglib"
}

ffbuild_cflags() {
    echo "-DGLIB_STATIC_COMPILATION"
}

ffbuild_ldflags() {
    # Glib требует системные библиотеки Windows при линковке
    echo "-lws2_32 -lole32 -lshlwapi -luserenv -lsetupapi -liphlpapi"
}
