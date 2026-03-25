#!/bin/bash

SCRIPT_REPO="https://github.com/tesseract-ocr/tesseract.git"
SCRIPT_COMMIT="397887939a357f166f4674bc1d66bb155795f325"

ffbuild_depends() {
    echo leptonica-test
    echo libarchive
    echo libtensorflow-test
    echo pango
    echo cairo
    echo libtiff
    echo openssl
    echo libicu
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

log_debug "--- Tesseract debug STEP 1"
# Find which cmake config is injecting Ws2_32
grep -r "Ws2_32" "$FFBUILD_PREFIX" 2>/dev/null
grep -r "Ws2_32" /opt/ct-ng/x86_64-w64-mingw32/ 2>/dev/null | head -20

log_debug "--- Tesseract debug STEP 2"
grep -r "WINDOWS_EXPORT\|out-implib\|dll.a\|SHARED" \
    ../CMakeLists.txt ../src/CMakeLists.txt 2>/dev/null | head -20

    # ── Ws2_32 symlink ───────────────────────────────────────────────────────────
    local ws2="/opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libws2_32.a"
    [[ -f "$ws2" ]] && \
        ln -sf "$ws2" /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libWs2_32.a \
        2>/dev/null || true

    # ── Nuke ALL cmake find configs so CMake cannot append libs behind our back ──
    find "$FFBUILD_PREFIX/lib/cmake" \
        \( -name "*Config.cmake" \
           -o -name "*-config.cmake" \
           -o -name "*Targets*.cmake" \
           -o -name "*targets*.cmake" \) \
        -delete 2>/dev/null || true
    # Also nuke pkgconfig for libs we manage manually so CMake's pkg_check_modules
    # doesn't find them and add them to INTERFACE_LINK_LIBRARIES
    # (we keep them for our own pkg-config calls, but hide from CMake's scanner)
    # We do this by temporarily renaming the dir during cmake configure
    local pkgcfg_backup="/opt/ffbuild_pkgcfg_backup"
    cp -r "$FFBUILD_PREFIX/lib/pkgconfig" "$pkgcfg_backup" 2>/dev/null || true

    # ── Full lib list (flat, no group — we add group after configure) ────────────
    local ALL_LIBS="\
-lleptonica \
-lpangocairo-1.0 -lpangowin32-1.0 -lpangoft2-1.0 -lpango-1.0 \
-lcairo-gobject -lcairo \
-lharfbuzz-icu -lharfbuzz-subset -lharfbuzz-cairo \
-lharfbuzz-vector -lharfbuzz-raster -lharfbuzz \
-lfontconfig -lfreetype -lpixman-1 -lfribidi \
-lgio-2.0 -lgthread-2.0 -lglib-2.0 \
-lcurl -lssh -lssl -lcrypto \
-larchive \
-ltiffxx -ltiff -lopenjp2 -lturbojpeg -ljpeg -lpng16 -lgif \
-lwebpmux -lwebpdemux -lwebp -lwebpdecoder -lsharpyuv \
-llcms2_fast_float -llcms2_threaded -llcms2 \
-lxml2 -lpcre2-posix -lpcre2-8 -lffi -ljbig \
-lzstd -llzma \
-lbrotlienc -lbrotlidec -lbrotlicommon \
-lbz2 -lz \
-lintl -liconv -lcharset \
-lsicuin -lsicuuc -lsicudt \
-luserenv -lcrypt32 -lnormaliz -luuid \
-lgdi32 -lsetupapi -lole32 -lshlwapi \
-luser32 -ladvapi32 -ldbghelp \
-lws2_32 -lwinmm -lbcrypt \
-lpthread -lstdc++ -lm"

    # Strip -Wl,-Bstatic — blocks import libs needed for __imp_ symbols
    local RAW_LDFLAGS
    RAW_LDFLAGS=$(echo "$LDFLAGS" | sed 's/-Wl,-Bstatic\b//g')

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTS=OFF
        -DBUILD_TRAINING_TOOLS=OFF
        -DWINDOWS_EXPORT_ALL_SYMBOLS=OFF
        -Dlibtesseract_type=STATIC
        -DOPENMP_BUILD=OFF
        -DFAST_FLOAT=ON
        -DSW_BUILD=OFF
        -DENABLE_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DLeptonica_DIR=OFF
        -DLEPT_TIFF_RESULT=0
        -DLEPT_TIFF_COMPILE_SUCCESS=ON
        -DCMAKE_FIND_LIBRARY_SUFFIXES=".a"
        -DPKG_CONFIG_EXECUTABLE="$(command -v pkg-config)"
        -DCMAKE_CXX_FLAGS="$CXXFLAGS $CPPFLAGS \
-DCURL_STATICLIB -DLIBARCHIVE_STATIC -DPTW32_STATIC_LIB \
-DWIN32_LEAN_AND_MEAN -D_WINSOCK_DEPRECATED_NO_WARNINGS \
-Wno-narrowing -Wno-format"
        -DCMAKE_C_FLAGS="$CFLAGS $CPPFLAGS \
-DCURL_STATICLIB -DLIBARCHIVE_STATIC -DPTW32_STATIC_LIB \
-DWIN32_LEAN_AND_MEAN -D_WINSOCK_DEPRECATED_NO_WARNINGS \
-Wno-narrowing -Wno-format"
        -DCMAKE_EXE_LINKER_FLAGS="$RAW_LDFLAGS $ALL_LIBS \
-Wl,--allow-multiple-definition"
        -DCMAKE_SHARED_LINKER_FLAGS="$RAW_LDFLAGS $ALL_LIBS \
-Wl,--allow-multiple-definition"
    )

    cmake "${myconf[@]}" .. || return 1

    # ── POST-CONFIGURE PATCHES ───────────────────────────────────────────────────

log_debug "--- Tesseract debug STEP 3"
    # 1. Clear INTERFACE_LINK_LIBRARIES on libtesseract target
    #    so CMake doesn't dump them into linkLibs.rsp outside our group
    find build -name "*.cmake" \
        | xargs grep -l "INTERFACE_LINK_LIBRARIES" 2>/dev/null \
        | while read -r f; do
            log_debug "Clearing INTERFACE_LINK_LIBRARIES in $f"
            sed -i \
                's/INTERFACE_LINK_LIBRARIES "[^"]*"/INTERFACE_LINK_LIBRARIES ""/g' \
                "$f"
        done

log_debug "--- Tesseract debug STEP 4"
    # 2. Patch all link.txt files:
    #    - fix capitalisation
    #    - remove --out-implib (we don't want a dll import lib)
    #    - wrap everything from first -l to end in --start-group/--end-group
    find build -name "link.txt" | while read -r lt; do
        log_debug "Patching link.txt: $lt"
        # Fix capitalisation
        sed -i 's/-lWs2_32\b/-lws2_32/g; s/-lWinmm\b/-lwinmm/g' "$lt"
        # Remove dll import lib output (causes confusion)
        sed -i 's/-Wl,--out-implib,[^ ]*//g' "$lt"
        # Remove any existing group markers
        sed -i 's/-Wl,--start-group[[:space:]]*//g
                s/[[:space:]]*-Wl,--end-group//g' "$lt"
        # Wrap: --start-group before first -l, --end-group at end of line
        sed -i 's/ -l/ -Wl,--start-group -l/
                s/$/ -Wl,--end-group/' "$lt"
        log_debug "Patched link.txt content:"
        cat "$lt" | tr ' ' '\n' | grep -E "group|lWs2|lws2|rsp" \
            | head -20 >&2 || true
    done

log_debug "--- Tesseract debug STEP 5"
    # Remove WINDOWS_EXPORT_ALL_SYMBOLS and out-implib from all cmake files
    find build -name "*.cmake" -o -name "Makefile" \
        | xargs sed -i \
            's/WINDOWS_EXPORT_ALL_SYMBOLS//g
             s/-Wl,--out-implib,[^ "]*//g' \
        2>/dev/null || true

    # ── Build pass 1 (generates linkLibs.rsp) ───────────────────────────────────
    log_debug "Build pass 1..."
    make -j$(nproc) $MAKE_V 2>&1 || true

    # ── Fix capitalisation in generated .rsp files ───────────────────────────────
    find build -name "*.rsp" | while read -r rsp; do
        log_debug "Patching rsp: $rsp"
        sed -i \
            's/-lWs2_32\b/-lws2_32/g
             s/-lWinmm\b/-lwinmm/g
             s/-lPthread\b/-lpthread/g' \
            "$rsp"
    done

log_debug "--- Tesseract debug STEP 6"
    # ── Log what linkLibs.rsp actually contains ──────────────────────────────────
    log_debug "=== linkLibs.rsp contents after pass 1 ==="
    find build -name "linkLibs.rsp" -exec cat {} \; \
        | tr ' ' '\n' | sort -u >&2 || true

log_debug "--- Tesseract debug STEP 7"
    log_debug "=== FULL link.txt after patching ==="
    find build -name "link.txt" -exec cat {} \; >&2

    # ── Build pass 2 (actual final link with fixed rsp files) ───────────────────
    log_debug "Build pass 2..."
    make -j$(nproc) $MAKE_V || return 1

    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

log_debug "--- Tesseract debug STEP 8"

    log_debug "=== linkLibs.rsp full content ==="
    find build -name "linkLibs.rsp" -exec echo "FILE: {}" \; -exec cat {} \; >&2
}

ffbuild_configure() {
    echo --enable-libtesseract
}

ffbuild_unconfigure() {
    echo --disable-libtesseract
}