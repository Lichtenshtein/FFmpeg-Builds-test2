#!/bin/bash

SCRIPT_REPO="https://github.com/facebook/jemalloc.git"
SCRIPT_COMMIT="6ced85a8e5d73e882aa999a1fbc95b9312461804"

ffbuild_enabled() {
    # [[ $TARGET == win* ]] || return 1
    return -1
}


ffbuild_dockerbuild() {

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --with-jemalloc-prefix=je_
        --disable-initial-exec-tls
        --with-lg-quantum=3
        --enable-autogen
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    export CPPFLAGS="$CPPFLAGS -I$FFBUILD_PREFIX/include"

    echo "Libs.private: @LIBS@" >> jemalloc.pc.in
    echo "jemalloc_prefix=@JEMALLOC_PREFIX@" >> jemalloc.pc.in
    CFLAGS="${CFLAGS/-fPIC/}"
    CFLAGS="${CFLAGS/-DPIC/}"
    export CFLAGS="${CFLAGS/-fno-semantic-interposition/} -fPIE"
    CXXFLAGS="${CXXFLAGS/-fPIC/}"
    CXXFLAGS="${CXXFLAGS/-DPIC/}"
    export CXXFLAGS="${CXXFLAGS/-fno-semantic-interposition/} -fPIE"

    ./autogen.sh "${myconf[@]}"
    make $MAKE_V -j$(nproc) build_lib_static
    make DESTDIR="$FFBUILD_DESTDIR" install_include install_lib_static install_lib_pc

#    ./autogen.sh "${myconf[@]}"
#    make -j$(nproc)
#    make install DESTDIR="$FFBUILD_DESTDIR"

 #   if [[ $VARIANT == *shared* ]]; then
 #       mv "$FFBUILD_PREFIX"/lib/libjemalloc{_pic,}.a
 #   else
 #       rm "$FFBUILD_PREFIX"/lib/libjemalloc_pic.a
 #   fi

}

ffbuild_configure() {
    echo --custom-allocator=jemalloc
}
