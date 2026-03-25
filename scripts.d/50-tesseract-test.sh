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

    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"

log_debug "--- Tesseract debug START"

# 2 Check what pkg-config actually reports for the key libraries
log_debug "--- Tesseract debug STEP 2"

for lib in leptonica libtiff-4 libarchive libcurl openssl; do
    log_debug "=== $lib ==="
    pkg-config --static --libs "$lib" 2>&1
done

# 3 Check the actual .a archives for undefined symbols
log_debug "--- Tesseract debug STEP 3"

# What does libtiff.a need that it doesn't provide itself?
nm -u /opt/ffbuild/lib/libtiff.a 2>/dev/null \
    | grep -v "^/" | awk '{print $2}' | sort -u \
    | head -40
nm -u /opt/ffbuild/lib/libleptonica.a 2>/dev/null \
    | grep -v "^/" | awk '{print $2}' | sort -u \
    | head -40

# 4 Check if the symbols actually exist in built libs
log_debug "--- Tesseract debug STEP 4"

# Does libz.a actually provide 'inflate'?
nm /opt/ffbuild/lib/libz.a | grep " T inflate$"
# Does libjpeg.a provide 'jpeg_read_header'?
nm /opt/ffbuild/lib/libjpeg.a | grep " T jpeg_read_header"
# Does libzstd.a provide 'ZSTD_compressStream'?
nm /opt/ffbuild/lib/libzstd.a | grep " T ZSTD_compressStream"
# Does libbrotlidec.a provide 'BrotliDecoderGetErrorCode'?
nm /opt/ffbuild/lib/libbrotlidec.a | grep "BrotliDecoderGetErrorCode"


    # исправляем фантомную libWs2_32 от которой компилятор падает
    # Создаем симлинк libWs2_32.a -> libws2_32.a
    # линкер найдет библиотеку при любом регистре
    # mkdir -p "$FFBUILD_PREFIX/lib"
    # ln -sf /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libws2_32.a \
           # /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libWs2_32.a 2>/dev/null || true
    # ln -sf /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libws2_32.a \
           # "$FFBUILD_PREFIX/lib/libWs2_32.a" 2>/dev/null || true

    # Удаляем "ядовитые" CMake-конфиги TIFF и других либ, 
    # которые заставляют линкер искать ZLIB::ZLIB

    # This prevents CMake from appending its own -l flags OUTSIDE our group.
    # rm -rf "$FFBUILD_PREFIX/lib/cmake"/{Leptonica,tiff,TIFF,ZLIB,zlib,libarchive,\
      # LibArchive,LibXml2,libxml2,CURL,curl,OpenSSL,openssl,libssh,LibSSH,\
      # brotli,Brotli,zstd,Zstd,lzma,LibLZMA,bzip2,BZip2,PNG,libpng,\
      # WebP,libwebp,GIF,giflib,OpenJPEG,openjpeg,Freetype,freetype,\
      # Fontconfig,fontconfig,HarfBuzz,harfbuzz,Fribidi,fribidi,\
      # Cairo,cairo,Pango,pango,GLib,glib,ICU,icu,PCRE2,pcre2,\
      # Pixman,pixman,LCMS2,lcms2} 2>/dev/null || true

    # Also nuke any stray *Config.cmake / *-config.cmake that survived
    # find "$FFBUILD_PREFIX/lib/cmake" -name "*Config.cmake" \
         # -o -name "*-config.cmake" 2>/dev/null | xargs rm -f 2>/dev/null || true

    # Backuping instead of deleting

    # Определяем путь к бэкапу
    CMAKE_BACKUP_DIR="/tmp/ffbuild_cmake_backup"

    # Если бэкап уже есть (от прошлого неудачного рана), удаляем его
    rm -rf "$CMAKE_BACKUP_DIR"
    mkdir -p "$CMAKE_BACKUP_DIR"

    # Перемещаем ВСЁ содержимое папки cmake в бэкап
    if [ -d "$FFBUILD_PREFIX/lib/cmake" ]; then
        log_info "Backing up CMAKE files for Tesseract..."
        mv "$FFBUILD_PREFIX/lib/cmake"/* "$CMAKE_BACKUP_DIR/" 2>/dev/null || true
    fi

    # LINKING HELL START

    # Library groups (ordered: high-level → low-level)
    # Rule: if A uses B, A must appear before B inside --start-group.
    # Inside the group the linker does multiple passes, so strict order is not
    # required for correctness, but keeping it logical helps debugging.

    # Tesseract's direct deps
    # the lib being built; CMake adds this itself
    local TESS_DIRECT="-ltesseract"

    # Leptonica + its image-format deps
    local LEPT="-lleptonica"
    local IMAGES="-ltiffxx -ltiff -lopenjp2 -lturbojpeg -ljpeg -lpng16 -lgif -lwebpmux -lwebpdemux -lwebp -lwebpdecoder -lsharpyuv"

    # Network / archive stack
    local NET="-lcurl -lssh -lssl -lcrypto"
    local ARCHIVE="-larchive"

    # Color management (lcms2 with fast-float and threaded plugins)
    local LCMS="-llcms2_fast_float -llcms2_threaded -llcms2"

    # Font / rendering stack
    local PANGO="-lpangocairo-1.0 -lpangowin32-1.0 -lpangoft2-1.0 -lpango-1.0"
    local CAIRO="-lcairo-gobject -lcairo"
    local HARFBUZZ="-lharfbuzz-icu -lharfbuzz-subset -lharfbuzz-cairo -lharfbuzz-vector -lharfbuzz-raster -lharfbuzz"
    local FONT="-lfontconfig -lfreetype -lpixman-1 -lfribidi"
    local GLIB="-lgio-2.0 -lgthread-2.0 -lglib-2.0"

    # Low-level / compression
    local COMPRESS="-lxml2 \
      -lpcre2-posix -lpcre2-8 \
      -lffi \
      -ljbig \
      -lzstd \
      -llzma \
      -lbrotlienc -lbrotlidec -lbrotlicommon \
      -lbz2 \
      -lz"

    # Internationalisation
    local INTL="-lintl -liconv -lcharset"

    # ICU (order matters: in → uc → dt)
    local ICU="-lsicuin -lsicuuc -lsicudt"

    # Windows system libs (bcrypt must follow anything using BCrypt* symbols)
    local WIN_SYS="-luserenv -lcrypt32 -lnormaliz -luuid \
      -lgdi32 -lsetupapi -lole32 -lshlwapi \
      -luser32 -ladvapi32 -ldbghelp \
      -lws2_32 -lwinmm -lbcrypt \
      -pthread -lstdc++ -lm"

    # Assemble the full linker command
    # Everything goes inside --start-group so the linker does multiple passes.
    # We also add a SECOND pass of the compression/system libs after --end-group
    # as a safety net for anything CMake appends after our flags.
    local INNER="$LEPT $PANGO $CAIRO $HARFBUZZ $FONT $GLIB \
      $NET $ARCHIVE \
      $IMAGES $LCMS \
      $COMPRESS $INTL $ICU \
      $WIN_SYS"

    # Склеиваем всё в ОДНУ огромную группу
    local FINAL_LIBS="-Wl,--start-group $INNER -Wl,--end-group"

    # RAW_LDFLAGS = LDFLAGS without -Wl,-Bstatic (already implied by our static libs)
    # Keep -static -static-libgcc -static-libstdc++ but drop the -Bstatic
    # because some mingw sysroot stubs are import libs and need dynamic resolution.
    local RAW_LDFLAGS=$(echo "$LDFLAGS" | sed 's/-Wl,-Bstatic//g')

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTS=OFF
        -DBUILD_TRAINING_TOOLS=OFF
        # -DBUILD_TRAINING_TOOLS=ON # Disable tools if they cause link errors
        # -DOPENMP_BUILD=ON # OpenMP в статике Mingw часто дает undefined reference на GOMP
        -DOPENMP_BUILD=OFF
        -DFAST_FLOAT=ON
        -DSW_BUILD=OFF
        -DENABLE_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        # Tell CMake NOT to use find_package / pkg-config for these
        # We supply everything manually; CMake must not append extra -l flags.
        -DCMAKE_DISABLE_FIND_PACKAGE_TIFF=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_PNG=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_JPEG=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_ZLIB=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_CURL=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_LibArchive=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_LibXml2=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_ICU=ON
        # Leptonica use our manual path, not CMake target
        -DLeptonica_DIR=OFF
        -DLEPT_TIFF_RESULT=0
        -DLEPT_TIFF_COMPILE_SUCCESS=ON
        # Explicit library paths so CMake's try_compile doesn't fail
        -DTIFF_LIBRARY="$FFBUILD_PREFIX/lib/libtiff.a"
        -DTIFF_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DPNG_LIBRARY="$FFBUILD_PREFIX/lib/libpng16.a"
        -DPNG_PNG_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DJPEG_LIBRARY="$FFBUILD_PREFIX/lib/libjpeg.a"
        -DJPEG_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DZLIB_LIBRARY="$FFBUILD_PREFIX/lib/libz.a"
        -DZLIB_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DLeptonica_LIBRARIES="$FFBUILD_PREFIX/lib/libleptonica.a"
        -DLeptonica_INCLUDE_DIRS="$FFBUILD_PREFIX/include/leptonica"
        -DCMAKE_FIND_LIBRARY_SUFFIXES=".a"
        -DPKG_CONFIG_EXECUTABLE="$(command -v pkg-config)"
        # Compiler flags
        -DCMAKE_CXX_FLAGS="$CXXFLAGS $CPPFLAGS -DCURL_STATICLIB -DLIBARCHIVE_STATIC -DPTW32_STATIC_LIB -DWIN32_LEAN_AND_MEAN -D_WINSOCK_DEPRECATED_NO_WARNINGS -Wno-narrowing -Wno-format"
        -DCMAKE_C_FLAGS="$CFLAGS $CPPFLAGS -DCURL_STATICLIB -DLIBARCHIVE_STATIC -DPTW32_STATIC_LIB -DWIN32_LEAN_AND_MEAN -D_WINSOCK_DEPRECATED_NO_WARNINGS -Wno-narrowing -Wno-format"
        # Linker flags
        # --allow-multiple-definition handles duplicate weak symbols from
        # mingw runtime + our static libstdc++/libgcc
        -DCMAKE_EXE_LINKER_FLAGS="$RAW_LDFLAGS $FINAL_LIBS -Wl,--allow-multiple-definition"
    )

    mkdir build && cd build

    cmake "${myconf[@]}" .. || return 1
    # make -j$(nproc) $MAKE_V || return 1

# 5 Check if CMake is actually using linker flags
# After cmake configure, look at what it generated
log_debug "--- Tesseract debug STEP 5"

cat build/CMakeFiles/libtesseract.dir/link.txt

# 6 Check for the __imp_ symbol problem specifically
# __imp_WSASetEvent etc. come from ws2_32
# Check if the sysroot has it
log_debug "--- Tesseract debug STEP 6"

nm /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libws2_32.a \
    | grep -i "WSASetEvent"
# Check if -Bstatic is blocking it
ls -la /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libws2_32*

# 7 Verify the actual .pc files that matter
log_debug "--- Tesseract debug STEP 7"

cat "$PC_DIR/leptonica.pc"
echo "---"
cat "$PC_DIR/libtiff-4.pc"
echo "---"  
cat "$PC_DIR/libarchive.pc"
echo "---"
cat "$PC_DIR/libcurl.pc"

log_debug "--- Tesseract debug END"

    make -j1 VERBOSE=1 2>&1 | grep -A5 "Linking CXX executable" | tee /tmp/tess_link.log || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Возвращаем cmake файлы обратно в префикс
    if [ -d "$CMAKE_BACKUP_DIR" ]; then
        mkdir -p "$FFBUILD_PREFIX/lib/cmake"
        log_info "Restoring CMAKE files from backup..."
        mv "$CMAKE_BACKUP_DIR"/* "$FFBUILD_PREFIX/lib/cmake/" 2>/dev/null || true
        rm -rf "$CMAKE_BACKUP_DIR"
    fi

}

ffbuild_configure() {
    echo --enable-libtesseract
}

ffbuild_unconfigure() {
    echo --disable-libtesseract
}