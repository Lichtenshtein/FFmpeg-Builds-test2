#!/bin/bash

SCRIPT_REPO="https://github.com/tesseract-ocr/tesseract.git"
SCRIPT_COMMIT="397887939a357f166f4674bc1d66bb155795f325"

ffbuild_depends() {
    echo leptonica
    echo libarchive
    echo pango
    echo cairo
    echo libtiff
    echo openssl
    echo libicu
    echo libcurl
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    log_debug "Patching CMakeLists.txt to fix case-sensitivity and disable executable..."
    # Fix Ws2_32 case
    find . -type f -name "CMakeLists.txt" -exec sed -i 's/Ws2_32/ws2_32/g' {} +
    # Disable the tesseract executable target and its links
    sed -i 's@^add_executable(tesseract@# add_executable(tesseract@g' CMakeLists.txt
    sed -i 's@^target_link_libraries(tesseract@# target_link_libraries(tesseract@g' CMakeLists.txt
    sed -i 's@install(TARGETS tesseract@# install(TARGETS tesseract@g' CMakeLists.txt

    mkdir -p build && cd build

    # Backing up "poisoned" CMake-конфиги TIFF и других либ, 
    # которые заставляют линкер искать ZLIB::ZLIB
    # This prevents CMake from appending its own -l flags OUTSIDE our group.
    local cmake_backup="/tmp/cmake_backup_tesseract"
    mkdir -p "$cmake_backup"
    log_debug "Backing up existing CMake configs to prevent interference..."
    find "$FFBUILD_PREFIX/lib/cmake" \
        \( -name "*Config.cmake" \
           -o -name "*-config.cmake" \
           -o -name "*Targets*.cmake" \
           -o -name "*targets*.cmake" \) \
        -exec mv -t "$cmake_backup" {} + 2>/dev/null || true

    # Back up real (not a symlink) g++ and install wrapper
    # local gxx_proxy="/usr/local/bin/x86_64-w64-mingw32-g++"
    # Определяем, где на самом деле лежит g++ (прокси или реальный)

    # Create a CXX compiler wrapper that intercepts the final link
    # When the wrapper sees --whole-archive (the tesseract link step),
    # it rewrites the command to wrap ALL -l flags AND bare .a files in one group.
    # Делаем бэкап только если это еще не сделано
    local gxx_proxy=$(command -v x86_64-w64-mingw32-g++)
    local gxx_bak="${gxx_proxy}.bak"
    local wrapper="${gxx_proxy}-wrapper"

    if [[ -z "$gxx_proxy" ]]; then
        log_error "Compiler x86_64-w64-mingw32-g++ not found in PATH"
        return 1
    fi

    if [[ ! -f "$gxx_bak" ]]; then
        cp -a "$gxx_proxy" "$gxx_bak"

        cat > "$wrapper" << 'WRAPPER_EOF'
#!/bin/bash
# Transparent wrapper around x86_64-w64-mingw32-g++
# Intercepts the final executable link and fixes library ordering.
REAL_GXX="${0}.bak"

# Only intercept executable links (they contain --whole-archive)
if printf '%s\n' "$@" | grep -e '\.exe' -e '\.dll' -e '--whole-archive' | grep -q -- '-o'; then
    # Expand all @response_files into a flat argument list
    expanded=()
    for arg in "$@"; do
        if [[ "$arg" == @* ]]; then
            rsp="${arg#@}"
            if [[ -f "$rsp" ]]; then
                # Read rsp, splitting on spaces and newlines
                while IFS= read -r token || [[ -n "$token" ]]; do
                    for t in $token; do
                        expanded+=("$t")
                    done
                done < "$rsp"
            else
                expanded+=("$arg")
            fi
        else
            expanded+=("$arg")
        fi
    done

    # Now rebuild the command in correct order:
    # compiler_flags ... -Wl,--whole-archive objects -Wl,--no-whole-archive
    # -o output
    # -Wl,--start-group [ALL libs] -Wl,--end-group
    # [extra flags]

    pre=()        # compiler + flags before --whole-archive
    objects=()    # --whole-archive ... --no-whole-archive block
    output=()     # -o output [--out-implib ...]
    libs=()       # all -l flags and bare .a files
    post=()       # trailing flags (--major-image-version etc.)

    in_whole=0
    skip_next=0
    i=0
    while [[ $i -lt ${#expanded[@]} ]]; do
        arg="${expanded[$i]}"

        # Fix capitalisation
        arg="${arg//-lWs2_32/-lws2_32}"
        arg="${arg//-lWinmm/-lwinmm}"
        arg="${arg//-lPthread/-lpthread}"

        if [[ $skip_next -eq 1 ]]; then
            skip_next=0
            ((i++))
            continue
        fi

        case "$arg" in
            # Strip --out-implib (we don't want a dll import lib side effect)
            -Wl,--out-implib,*)
                : ;;
            --out-implib)
                skip_next=1 ;;

            # Absorb existing group markers — we'll add our own
            -Wl,--start-group|-Wl,--end-group)
                : ;;

            # Capture --whole-archive block into objects[]
            -Wl,--whole-archive)
                in_whole=1
                objects+=("$arg") ;;
            -Wl,--no-whole-archive)
                in_whole=0
                objects+=("$arg") ;;

            # Capture output target
            -o)
                output+=("-o" "${expanded[$((i+1))]}")
                ((i++)) ;;

            # Capture all lib flags and bare .a files into libs[]
            # Все, что похоже на библиотеку или поиск пути, кидаем в группу
            -l*|-L*|*.a|*.lib)
                if [[ $in_whole -eq 0 ]]; then
                    libs+=("$arg")
                else
                    objects+=("$arg")
                fi ;;

            # Version flags go to post
            -Wl,--major-image-version,*|-Wl,--minor-image-version,*)
                post+=("$arg") ;;

            # Everything else goes to pre (compiler flags)
            *)
                if [[ $in_whole -eq 0 && ${#objects[@]} -eq 0 ]]; then
                    pre+=("$arg")
                elif [[ $in_whole -eq 1 ]]; then
                    objects+=("$arg")
                else
                    post+=("$arg")
                fi ;;
        esac
        ((i++))
    done

    # Reconstruct: pre + objects + output + --start-group libs --end-group + post
    exec "$REAL_GXX" \
        "${pre[@]}" \
        "${objects[@]}" \
        "${output[@]}" \
        -Wl,--start-group \
            "${libs[@]}" \
        -Wl,--end-group \
        -Wl,--allow-multiple-definition \
        "${post[@]}"
else
    # Not a final link — pass through unchanged
    exec "$REAL_GXX" "$@"
fi
WRAPPER_EOF

        chmod +x "$wrapper"
        ln -sf "$wrapper" "$gxx_proxy"
        log_debug "Installed g++ wrapper at $gxx_proxy"
    fi

    restore_gxx() {
        if [[ -f "$gxx_bak" ]]; then
            mv -f "$gxx_bak" "$gxx_proxy"
            log_debug "Restored real g++ at $gxx_proxy"
        fi
    }
    trap restore_gxx EXIT

    # Full lib list (flat, no group; we add group after configure)
    local ALL_LIBS="\
-lleptonica \
-lpangocairo-1.0 -lpangowin32-1.0 -lpangoft2-1.0 -lpango-1.0 \
-lcairo-gobject -lcairo \
-lharfbuzz-icu -lharfbuzz-subset -lharfbuzz-cairo \
-lharfbuzz-vector -lharfbuzz-raster -lharfbuzz \
-lfontconfig -lfreetype -lpixman-1 -lfribidi \
-lgio-2.0 -lgthread-2.0 -lglib-2.0 \
-lcurl -lquiche -lnghttp2 -lssh -lssl -lcrypto \
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
-lgdi32 -lsetupapi -lole32 -lshlwapi -liphlpapi \
-luser32 -ladvapi32 -ldbghelp -lwldap32 \
-lws2_32 -lwinmm -lbcrypt  \
-pthread -lstdc++ -lm \
-lusp10 -lmsimg32 -lruntimeobject \
-ldwrite -ld2d1 -lwindowscodecs -lopengl32"

    # Strip -Wl,-Bstatic — blocks import libs needed for __imp_ symbols
    local RAW_LDFLAGS=$(echo "$LDFLAGS" | sed 's/-Wl,-Bstatic\b//g')

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DCURL_STATICLIB -DLIBARCHIVE_STATIC -DPTW32_STATIC_LIB"

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_TESTS=OFF
        -DBUILD_TRAINING_TOOLS=OFF # causes strange pgp path '=/include' errors
        -DOPENMP_BUILD=$([[ $target != "win64" && "${USE_OPENMP}" == "1" ]] && echo ON || echo OFF) # DO NOT enable it for Win64
        -DFAST_FLOAT=ON
        -DSW_BUILD=OFF
        # -DENABLE_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        # Leptonica use our manual path, not CMake target
        -DLeptonica_DIR=OFF
        -DLEPT_TIFF_RESULT=0
        -DLEPT_TIFF_COMPILE_SUCCESS=ON
        # Explicit library paths so CMake's try_compile doesn't fail
        -DCMAKE_FIND_LIBRARY_SUFFIXES=".a"
        -DPKG_CONFIG_EXECUTABLE="$(command -v pkg-config)"
        # Compiler flags
        -DCMAKE_CXX_FLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags -DWIN32_LEAN_AND_MEAN -D_WINSOCK_DEPRECATED_NO_WARNINGS -Wno-narrowing -Wno-format"
        -DCMAKE_C_FLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags -DWIN32_LEAN_AND_MEAN -D_WINSOCK_DEPRECATED_NO_WARNINGS -Wno-narrowing -Wno-format"
        # Linker flags
        -DCMAKE_EXE_LINKER_FLAGS="$RAW_LDFLAGS ${USELTO} -Wl,--no-as-needed $ALL_LIBS -Wl,--as-needed -Wl,--allow-multiple-definition"
        -DCMAKE_SHARED_LINKER_FLAGS="$RAW_LDFLAGS ${USELTO} -Wl,--no-as-needed $ALL_LIBS -Wl,--as-needed -Wl,--allow-multiple-definition"
    )

    cmake -G Ninja "${myconf[@]}" .. || return 1

    # Clear INTERFACE_LINK_LIBRARIES (belt and suspenders)
    find . -name "TesseractTargets.cmake" \
        -o -name "*Targets*.cmake" 2>/dev/null \
    | xargs grep -l "INTERFACE_LINK_LIBRARIES" 2>/dev/null \
    | while read -r f; do
        log_debug "Clearing INTERFACE_LINK_LIBRARIES in $f"
        sed -i \
            's/INTERFACE_LINK_LIBRARIES "[^"]*"/INTERFACE_LINK_LIBRARIES ""/g' \
            "$f"
    done

    # Собираем только библиотеку
    ninja $NINJA_V libtesseract || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Возвращаем старые конфиги назад (не затирая новые от самого tesseract)
    log_debug "Restoring backed up CMake configs..."
    cp -n "$cmake_backup"/* "$FFBUILD_PREFIX/lib/cmake/" 2>/dev/null || true
    rm -rf "$cmake_backup"

    log_debug "=== linkLibs.rsp full content ==="
    find . -name "linkLibs.rsp" -exec echo "FILE: {}" \; -exec cat {} \; >&2
}

ffbuild_configure() {
    echo --enable-libtesseract
}

ffbuild_unconfigure() {
    echo --disable-libtesseract
}