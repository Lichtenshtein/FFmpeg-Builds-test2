#!/bin/bash
SCRIPT_REPO="https://github.com/GNOME/glib.git"
SCRIPT_COMMIT="2.80.0"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    # Подготавливаем кросс-файл более надежным способом
    # Используем уже имеющийся в образе /cross.meson как базу или создаем свой
    
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
pkgconfig = 'pkg-config'
strip = '${FFBUILD_TOOLCHAIN}-strip'
windres = '${FFBUILD_TOOLCHAIN}-windres'
nm = '${FFBUILD_TOOLCHAIN}-gcc-nm'
ranlib = '${FFBUILD_TOOLCHAIN}-gcc-ranlib'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = [$(echo $CFLAGS | sed "s/[^ ]* /'&', /g;s/[^ ]*$/'&'/")]
cpp_args = [$(echo $CXXFLAGS | sed "s/[^ ]* /'&', /g;s/[^ ]*$/'&'/")]
c_link_args = [$(echo $LDFLAGS | sed "s/[^ ]* /'&', /g;s/[^ ]*$/'&'/")]
cpp_link_args = [$(echo $LDFLAGS | sed "s/[^ ]* /'&', /g;s/[^ ]*$/'&'/")]
EOF

    # Настройка Meson
    # Добавляем -Dglib_static=true для корректных макросов в заголовках
    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file cross_file.txt \
        --buildtype release \
        --default-library static \
        -Dtests=false \
        -Dintrospection=disabled \
        -Dlibmount=disabled \
        -Dglib_static=true \
        -Dnls=disabled \
        -Dforce_posix_threads=true

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
