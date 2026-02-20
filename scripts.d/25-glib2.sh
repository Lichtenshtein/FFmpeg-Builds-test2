#!/bin/bash
SCRIPT_REPO="https://github.com/GNOME/glib.git"
SCRIPT_COMMIT="6b11cae1b3bf3e9cff9485481dd1c0f7e806c361"
# SCRIPT_COMMIT="2.80.0"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
    echo "git submodule update --quiet --init --recursive --depth 1"
}

ffbuild_dockerbuild() {
    set -e
    # Удаляем только pcre2 из субпроектов, чтобы заставить использовать наш билд
    rm -rf subprojects/pcre2*

    # инициализация подмодуля gvdb
    if ! git submodule update --init --recursive; then
        echo "Submodule update failed, downloading GVDB manually..."
        rm -rf subprojects/gvdb
        git clone --depth 1 https://github.com/GNOME/gvdb.git subprojects/gvdb
    fi

    # Заставляем Meson использовать наш pcre2, zlib и libiconv через pkg-config
    export PKG_CONFIG_LIBDIR="$FFBUILD_PREFIX/lib/pkgconfig"
    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig"
    # Исправляем CFLAGS для корректной работы с MinGW
    export CFLAGS="$CFLAGS -D_G_WIN32_WINNT=0x0A00 -DG_WIN32_IS_STRICT_MINGW"
    export CXXFLAGS="$CXXFLAGS -D_G_WIN32_WINNT=0x0A00 -DG_WIN32_IS_STRICT_MINGW"

    # Превращаем строку CFLAGS в массив для Meson ['flag1', 'flag2']
    # Это более надежный способ обработки пробелов
    read -ra CFLAGS_ARR <<< "$CFLAGS"
    MESON_C_ARGS=$(printf "'%s', " "${CFLAGS_ARR[@]}" | sed 's/, $//')
    
    read -ra CXXFLAGS_ARR <<< "$CXXFLAGS"
    MESON_CXX_ARGS=$(printf "'%s', " "${CXXFLAGS_ARR[@]}" | sed 's/, $//')
    
    read -ra LDFLAGS_ARR <<< "$LDFLAGS"
    MESON_L_ARGS=$(printf "'%s', " "${LDFLAGS_ARR[@]}" | sed 's/, $//')

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

[built-in options]
c_args = [$MESON_C_ARGS]
cpp_args = [$MESON_CXX_ARGS]
c_link_args = [$MESON_L_ARGS]
cpp_link_args = [$MESON_L_ARGS]
EOF
    unset CC CXX CPP LD AR NM RANLIB STRIP


echo "int main(){return 0;}" > test.c
${FFBUILD_TOOLCHAIN}-gcc $CFLAGS test.c -o test.exe || (log_error "GCC is broken with current CFLAGS: $CFLAGS"; exit 1)



    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file cross_file.txt \
        --buildtype release \
        --default-library static \
        -Dtests=false \
        -Dintrospection=disabled \
        -Dlibmount=disabled \
        -Dnls=disabled \
        -Dgio_module_dir="$FFBUILD_PREFIX/lib/gio/modules"

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Проверяем наличие файла перед sed
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/glib-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Добавляем системные либы для статики, чтобы FFmpeg мог линковаться
        sed -i "s/Libs:/Libs: -lws2_32 -lole32 -lshlwapi -luserenv -lsetupapi -liphlpapi -lintl -liconv -lpthread /" "$PC_FILE"
    fi

    # Чистим мусор
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "*.dll.a" -delete || true
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
