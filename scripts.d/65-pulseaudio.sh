#!/bin/bash

SCRIPT_REPO="https://github.com/Luiz-Monad/libpulseaudio.git"
SCRIPT_COMMIT="dcf4d0523257b10d6b3e480e1fa56a397a00f0e2"

SCRIPT_MIRROR="https://gitlab.freedesktop.org/pulseaudio/pulseaudio.git"
SCRIPT_MIRROR_COMMIT="b096704c0d42c5e784deb781a07b23cfb5286a82"

ffbuild_depends() {
    echo base
    echo libiconv
    echo libsamplerate
    echo soxr
    echo openssl
    echo glib
    echo fftw
}

ffbuild_enabled() {
    [[ $TARGET == linux* ]] || return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Kill build of utils and their sndfile dep
    echo > src/utils/meson.build
    echo > src/pulsecore/sndfile-util.c
    echo > src/pulsecore/sndfile-util.h
    sed -ri -e 's/(sndfile_dep = .*)\)/\1, required : false)/' meson.build
    sed -ri -e 's/shared_library/library/g' src/meson.build src/pulse/meson.build

    mkdir -p build && cd build

    local myconf=(
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false )
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dcpp_std=c++17
        -Dc_std=c11
        -Ddaemon=false
        -Dclient=true
        -Ddoxygen=disabled
        -Dgcov=false
        -Dman=false
        -Dtests=disabled
        -Dipv6=true
        -Dopenssl=enabled
        -Dfftw=enabled
        -Dglib=enabled
    )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --cross-file="$FFBUILD_MESON_CROSS"
        )
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    rm -r "$FFBUILD_DESTPREFIX"/share

    sed -i '/^Libs.private:/ s/$/ -ldl -lrt -liconv/' "$PC_DIR/libpulse.pc"
    sed -i '/^Libs.private:/ s/$/ -ldl -lrt -liconv/' "$PC_DIR/libpulse-simple.pc"
}

ffbuild_configure() {
    echo --enable-libpulse
}

ffbuild_unconfigure() {
    echo --disable-libpulse
}
