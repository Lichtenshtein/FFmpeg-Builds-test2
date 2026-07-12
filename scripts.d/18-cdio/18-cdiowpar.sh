#!/bin/bash

SCRIPT_REPO="https://github.com/rocky/libcdio-paranoia.git"
SCRIPT_COMMIT="384f4dac7e211cce67a14f3df53fc596965b6c94"

ffbuild_depends() {
    echo libiconv
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf test"
}

ffbuild_dockerbuild() {
    set -e

    local DEP_LIBS="-liconv -lcharset"

    if [[ -f "Makefile.am" ]]; then
        log_info "Tweaking SUBDIRS in Makefile.am for libcdio-paranoia..."
        sed -i 's|SUBDIRS = doc include lib src test example|SUBDIRS = include lib src|g' Makefile.am
    fi

    if [[ -f "configure.ac" ]]; then
        log_info "Purging missing test, doc, and example paths from configure.ac..."
        sed -i '/doc\/Makefile/d' configure.ac
        sed -i '/doc\/doxygen/d' configure.ac
        sed -i '/doc\/en\//d' configure.ac
        sed -i '/doc\/ja\//d' configure.ac
        sed -i '/example\/Makefile/d' configure.ac
        sed -i '/example\/C++/d' configure.ac
        sed -i '/test\/data\/Makefile/d' configure.ac
        sed -i '/test\/cdda_interface\/Makefile/d' configure.ac
        sed -i '/test\/cdda_interface\/toc.c/d' configure.ac
        sed -i '/test\/Makefile/d' configure.ac
        sed -i '/AC_CONFIG_FILES(\[test\/check_/d' configure.ac
        sed -i '/AC_CONFIG_FILES(\[test\/endian.sh/d' configure.ac
    fi

    autoreconf -if

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-example-progs
        --disable-maintainer-mode
        --disable-cpp-progs
        --enable-cpp-progs=no
        --disable-cxx # Disable C++ bindings
        --with-pic
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    if [[ $TARGET == win64 ]]; then
        myconf+=(
            --without-versioned-libs
        )
    fi

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS $DEP_LIBS ${USELTO}${USELTO_L}" \
    LIBS="$LIBS $DEP_LIBS" \
    ac_cv_func_clock_gettime=no \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" bin_PROGRAMS="" || return 1

    mkdir -p "$PC_DIR"
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s|^Cflags:.*|& -I\${includedir}/cdio|" "$PC_FILE"
        done
        log_info "Cflags paths have been updated."
    fi
}

ffbuild_configure() {
    echo --enable-libcdio
}

ffbuild_unconfigure() {
    echo --disable-libcdio
}
