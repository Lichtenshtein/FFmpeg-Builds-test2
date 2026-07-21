#!/bin/bash

SCRIPT_REPO="https://github.com/Tomotz/flite.git"
SCRIPT_COMMIT="6ff94c999339a26281180c8b4ba3c89f2e1fcdf9"
SCRIPT_BRANCH="tomm-dump-ipa"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
# Remove BOM marker before patch
    cat <<EOF
sed -i '1s/^\xEF\xBB\xBF//' flite.sln
EOF
}

ffbuild_dockerbuild() {
    set -e

    # Patch the root Makefile.in to avoid building utilities (main) and tests
    if [ -f Makefile.in ]; then
        log_info "Patching Makefile.in to skip binaries generation..."
        sed -i 's/SUBDIRS = .*/SUBDIRS =  src lang/g' Makefile.in
    fi

    local myconf=(
        --host="$FFBUILD_TOOLCHAIN"
        --prefix="$FFBUILD_PREFIX"
        --with-audio=none # specific audio support (none linux freebsd etc)
        --with-mmap=win32 # mmap support (none posix win32)
        --with-lang=usenglish
        --with-lex=cmulex
        --with-vox=all
        # --with-langvox # with subsets of lang, lex and voices
        --with-pic
        --disable-sockets
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --enable-shared=yes ) || \
        myconf+=( --enable-shared=no --disable-shared )

    # Forcefully disabling sockets for stability
    export DEFS="-DCST_NO_SOCKETS -DUNDER_WINDOWS -DWIN32"

    CC_FOR_BUILD="gcc" \
    CFLAGS="$CFLAGS ${USELTO}${USELTO_C} -Wa,-mbig-obj" \
    CPPFLAGS="$CPPFLAGS -DWAIT_ANY=-1" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C} -Wa,-mbig-obj" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    # Preliminary creation of the structure
    mkdir -p build/${FFBUILD_TOOLCHAIN}/obj "$INSTALL_ROOT"/{lib/pkgconfig,include/flite}

    # Generate flite_voice_list.c and directories in exactly one thread
    make -j1 $MAKE_V || return 1

    # make install DESTDIR="$FFBUILD_DESTDIR"

    # Dynamic search for the lib folder (fix for x86_64-mingw32 vs x86_64-w64-mingw32)
    local BUILDIR=$(find build -maxdepth 3 -type d -name "lib" | head -n 1)
    if [[ -d "$BUILDIR" ]]; then
        log_info "Found build libraries in $BUILDIR"
        cp ${OP_VERB} "$BUILDIR"/*.a "$INSTALL_ROOT/lib/"
    else
        log_error "Could not find compiled libraries in build/ folder!"
        return 1
    fi

    # Copy the headers
    cp ${OP_VERB} include/*.h "$INSTALL_ROOT/include/flite/"

    # Compile a list of all libraries for Libs (according to flite.pc.in and reality)
    # The order is important: voices and lexicons first, -lflite last
    local VOX_LIBS=$(find "$INSTALL_ROOT/lib" -name "libflite_*.a" | sed "s|.*/lib\(flite_.*\)\.a|-l\1|" | xargs)

    cat <<EOF > "$PC_DIR/flite.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: Flite
Description: A text to speech library
Version: ${VER_FULL}
Libs: -L\${libdir} $VOX_LIBS -lflite
Cflags: -I\${includedir} -I\${includedir}/flite
EOF

# with ffmpeg patch we can load voices like this:
# ffmpeg.exe -f lavfi -i "flite=text='Hello':voicefile='C:/path/to/my/voice.flitevox'" out.wav
}

ffbuild_configure() {
    echo --enable-libflite
}

ffbuild_unconfigure() {
    echo --disable-libflite
}

ffbuild_libs() {
    echo "-lflite"
}
