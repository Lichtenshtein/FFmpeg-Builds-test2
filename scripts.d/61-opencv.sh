#!/bin/bash

SCRIPT_REPO="https://github.com/opencv/opencv.git"
SCRIPT_COMMIT="06574736b35bc3f6682c3e8d52624fcac64532b9"

ffbuild_depends() {
    echo vulkan-headers
    echo vulkan-loader
    echo glslang
    echo shaderc
    echo spirv-cross
    echo spirv-headers
    echo libjxl
    echo quirc
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf \
samples doc \
3rdparty/ffmpeg \
3rdparty/libjpeg \
3rdparty/libjpeg-turbo \
3rdparty/libpng \
3rdparty/libtiff \
3rdparty/libwebp \
3rdparty/openjpeg \
3rdparty/zlib \
3rdparty/zlib-ng \
data/haarcascades_cuda \
data/vec_files"
# haarcascades_cuda may need manual installation instead of cleaning if build on linux and cuda SDK is installed
}

ffbuild_dockerbuild() {
    set -e

    log_info "${BROOM_MARK} Patching CMake scripts to suppress warnings..."
    find . -name "CMakeLists.txt" -o -name "*.cmake" | xargs sed -i 's/-Wundef/-Wno-undef/g' 2>/dev/null || true

    PYTHON_ROOT=$(python3 -c "import sys; print(sys.prefix)")
    NUMPY_PATH=$(python3 -c "import numpy; print(numpy.get_include())")

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        # -DENABLE_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DOPENCV_GENERATE_PKGCONFIG=ON
        -DOPENCV_CHECK_COMPILER_FLAGS=OFF
        -DCMAKE_MAP_IMPORTED_CONFIG_DEBUG=Release
        -DCMAKE_POLICY_DEFAULT_CMP0091=NEW
        -DCPU_BASELINE=AVX2
        -DCPU_DISPATCH=AVX2
        -DENABLE_PIC=ON
        -DOPENCV_ENABLE_NONFREE=ON
        # don't build what we've already built
        -DBUILD_OPENEXR=ON
        -DBUILD_JASPER=ON # jpeg2k
        -DBUILD_PNG=OFF
        -DBUILD_SPNG=OFF
        # Disabling unnecessary components to speed up the build
        -DBUILD_EXAMPLES=OFF
        -DBUILD_PACKAGE=OFF
        -DBUILD_DOCS=OFF
        -DBUILD_TESTS=OFF
        -DBUILD_PERF_TESTS=OFF
        -DBUILD_FAT_JAVA_LIB=OFF
        -DBUILD_JAVA=OFF
        -DBUILD_opencv_model_diagnostics=OFF
        -DBUILD_opencv_apps=OFF
        -DBUILD_opencv_python2=OFF
        -DBUILD_opencv_java=OFF
        # installed version of numpy not suitable
        -DBUILD_opencv_python3=OFF
        # -DPYTHON3_INCLUDE_PATH="$PYTHON_ROOT/include/python3.12"
        # -DPYTHON3_LIBRARIES="$PYTHON_ROOT/lib/libpython3.12.so"
        # -DPYTHON3_NUMPY_INCLUDE_DIRS="$NUMPY_PATH"
        # -DOPENCV_SKIP_PYTHON_LOADER=ON
        # Enable formats
        -DWITH_MSMF_DXVA=ON
        -DWITH_PNG=ON
        -DWITH_SPNG=OFF
        -DWITH_JASPER=ON # build it
        -DWITH_OPENEXR=ON # build it
        -DWITH_OPENGL=ON
        # IPP
        -DBUILD_IPP_IW=ON
        -DWITH_IPP=ON
        -DOPENCV_IPP_ENABLE_ALL=ON
        -DIPP_IW_DISABLE_SEH=ON
        # Disable loading of ready-made FFmpeg DLLs
        -DOPENCV_FFMPEG_SKIP_DOWNLOAD=ON
        -DWITH_FFMPEG=OFF # ON if standalone
        # plugins
        -DHIGHGUI_ENABLE_PLUGINS=ON
        -DVIDEOIO_ENABLE_PLUGINS=ON
    )

    if has_library "openblas"; then
        log_info "OpenBLAS library detected. Building with OpenBLAS support..."
        myconf+=(
            -DWITH_LAPACK=ON
            -DOpenBLAS_LIBRARIES="$FFBUILD_PREFIX/lib/libopenblas.${lib_ext}"
            # -DOpenBLAS_INCLUDE_DIRS="$FFBUILD_PREFIX/include/openblas"
            # -DOpenBLAS_LAPACKE_DIR="$FFBUILD_PREFIX/lib/cmake/OpenBLAS"
            # -DLAPACK_INCLUDE_DIR="$FFBUILD_PREFIX/include/openblas"
            # -DLAPACK_LIBRARIES="$FFBUILD_PREFIX/lib/libopenblas.${lib_ext}"
        )
    fi
    if has_library "tiff"; then
        log_info "TIFF library detected. Building with TIFF support..."

        # Temporarily moving "poisoned" .cmake tiff files
        # local TIFF_CMAKE_DIR="$FFBUILD_PREFIX/lib/cmake/tiff"
        # local TIFF_HIDE_DIR="$TMP_DIR/tiff_hide"

        # mkdir -p "$TIFF_HIDE_DIR"

        # if [ -d "$TIFF_CMAKE_DIR" ]; then
            # log_info "Hiding TIFF CMake configs to force raw library usage..."
            # mv "$TIFF_CMAKE_DIR"/* "$TIFF_HIDE_DIR/"
        # fi

        # restore() {
            # if [ -n "${TIFF_HIDE_DIR}" ] && [ -d "${TIFF_HIDE_DIR}" ]; then
                # log_info "Restoring TIFF CMake files..."
                # shopt -s nullglob
                # local files=("${TIFF_HIDE_DIR}"/*)
                # if [ ${#files[@]} -gt 0 ]; then
                    # mv "${TIFF_HIDE_DIR}"/* "${TIFF_CMAKE_DIR}/"
                # fi
                # shopt -u nullglob
                # rm -rf "${TIFF_HIDE_DIR}"
            # fi
        # }
        # trap restore EXIT

        myconf+=(
            -DBUILD_TIFF=OFF
            -DWITH_TIFF=ON
            -DTIFF_INCLUDE_DIR="$FFBUILD_PREFIX/include"
            -DTIFF_LIBRARIES="$FFBUILD_PREFIX/lib/libtiff.${lib_ext};$FFBUILD_PREFIX/lib/libtiffxx.${lib_ext}"
            -DCMAKE_DISABLE_FIND_PACKAGE_TIFF=ON
            -DCMAKE_DISABLE_FIND_PACKAGE_Tiff=ON
        )
    fi
    if has_library "avif"; then
        log_info "AVIF library detected. Building with AVIF support..."
        myconf+=(
            -DWITH_AVIF=ON
            -DAVIF_INCLUDE_DIRS="$FFBUILD_PREFIX/include/avif"
            -DAVIF_LIBRARIES="$FFBUILD_PREFIX/lib/libavif.${lib_ext}"
        )
    fi
    if has_library "jpeg"; then
        log_info "JPEG library detected. Building with JPEG support..."
        myconf+=(
            -DBUILD_JPEG=OFF
            -DWITH_JPEG=ON
            -DJPEG_INCLUDE_DIR="$FFBUILD_PREFIX/include"
            -DJPEG_LIBRARIES="$FFBUILD_PREFIX/lib/libjpeg.${lib_ext};$FFBUILD_PREFIX/lib/libturbojpeg.${lib_ext}"
        )
    fi
    if has_library "z"; then
        log_info "ZLIB library detected. Building with ZLIB support..."
        myconf+=(
            -DBUILD_ZLIB=OFF
            -DZLIB_INCLUDE_DIR="$FFBUILD_PREFIX/include"
            -DZLIB_LIBRARY="$FFBUILD_PREFIX/lib/libz.${lib_ext}"
            -DZLIB_LIBRARIES="$FFBUILD_PREFIX/lib/libz.${lib_ext}"
            # -DWITH_ZLIB_NG=ON
        )
    fi
    if has_library "OpenCL"; then
        log_info "OpenCL library detected. Building with OpenCL support..."
        myconf+=(
            -DWITH_OPENCL=ON
            -DWITH_OPENCL_D3D11_NV=ON
            -DOPENCL_LIBRARIES="$FFBUILD_PREFIX/lib/libOpenCL.${lib_ext}"
            -DOPENCL_INCLUDE_DIR="$FFBUILD_PREFIX/include/CL"
        )
    fi
    if has_library "vulkan-1"; then
        log_info "Vulkan library detected. Building with Vulkan support..."
        myconf+=(
            -DWITH_VULKAN=ON
            -DVULKAN_LIBRARIES="$FFBUILD_PREFIX/lib/libvulkan-1.${lib_ext}"
            -DVULKAN_INCLUDE_DIRS="$FFBUILD_PREFIX/include/vulkan"
        )
    fi
    if has_library "openjp2"; then
        log_info "OpenJPEG library detected. Building with OpenJPEG support..."
        export OpenJPEG_DIR="$FFBUILD_PREFIX/lib/cmake/openjpeg-2.5"
        myconf+=(
            -DBUILD_OPENJPEG=OFF
            -DWITH_OPENJPEG=ON
            -DOPENJPEG_INCLUDE_DIR="$FFBUILD_PREFIX/include/openjpeg-2.5"
            -DOPENJPEG_LIBRARY="$FFBUILD_PREFIX/lib/libopenjp2.${lib_ext}"
        )
    fi
    if has_library "webp"; then
        log_info "WebP library detected. Building with WebP support..."
        myconf+=(
            -DBUILD_WEBP=OFF
            -DWITH_WEBP=ON
        )
    fi
    if has_library "openvino"; then
        log_info "OpenVINO library detected. Building with OpenVINO support..."
        # export OpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"
        export OpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"
        myconf+=(
            # Enabling integration with OpenVINO (Inference Engine)
            -DWITH_OPENVINO=$([ "${BUILD_VINO}" == "1" ] && echo ON || echo OFF)
            -DOPENVINO_STATIC_COMPILATION=$([[ "${PREFER_SHARED}" != "1" && "${BUILD_VINO}" == "1" ]] && echo ON || echo OFF)
            -DOpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"
            -DInferenceEngine_DIR="$FFBUILD_PREFIX/lib/cmake"
        )
    fi
    if has_library "quirc"; then
        log_info "QUIRC library detected. Building with QUIRC support..."
        myconf+=(
            -DWITH_QUIRC=ON
        )
    fi
    if has_library "jxl"; then
        log_info "JPEGXL library detected. Building with JPEGXL support..."
        myconf+=(
            -DWITH_JPEGXL=ON
        )
    fi
    if has_library "jbig"; then
        local JBIG_LIB="-ljbig"
    fi
    if has_library "tbbmalloc"; then
        log_info "TBB library detected. Building with TBB support..."
        myconf+=(
            -DBUILD_TBB=OFF
            -DWITH_TBB=$([ "${USE_OPENMP}" == "1" ] && echo OFF || echo ON)
            -DWITH_OPENMP=$([ "${USE_OPENMP}" == "1" ] && echo ON || echo OFF)
            -DTBB_INCLUDE_DIRS="$FFBUILD_PREFIX/include"
            -DTBB_LIB_DIR="$FFBUILD_PREFIX/lib"
        )
    elif [[ "${USE_OPENMP}" == "1" ]]; then
        log_info "Enabling OpenMP threading..."
        myconf+=(
            -DWITH_TBB=OFF
            -DWITH_OPENMP=ON
        )
    else
        log_info "Building with pthreads support..."
        myconf+=(
            -DWITH_PTHREADS_PF=ON
        )
    fi

    if [[ $TARGET == win64 ]]; then
        myconf+=(
        -DWITH_GSTREAMER=OFF
        -DWITH_WIN32UI=OFF
        -DWITH_GTK=OFF
        )
    elif [[ $TARGET == linux64 ]]; then
        myconf+=(
        -DWITH_GSTREAMER=ON
        # CUDA; linux only
        # -DWITH_CUDA=OFF # not supported
        # -DOPENCV_DNN_CUDA=ON
        # -DWITH_NVCUVID=ON
        # -DWITH_NVCUVENC=ON
        # -DCUDA_ARCH_BIN=6.1 # For example, for Pascal
        # -DCUDA_ARCH_PTX=6.1
        )
    fi

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-D__TBB_DYNAMIC_LOAD_ENABLED=0 -DOPENVINO_STATIC_LIBRARY"

    [[ "${USE_LTO}" == "1" ]] && LTO_FLAGS="-Wa,-mbig-obj"

    # -D_WIN32_WINNT=0x0600
    CFLAGS="$CFLAGS $CPPFLAGS ${OPENMP_C}${USELTO}${USELTO_C} $LTO_FLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${OPENMP_C}${USELTO}${USELTO_C} $LTO_FLAGS $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    LIBS="${JBIG_LIB} ${OPENMP_LIB}$LIBS $ADDITIONAL_LIBS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    mkdir -p "$INSTALL_ROOT"/{include,bin,lib/pkgconfig}

    local IPP_PATH="3rdparty/ippicv/ippicv_win/icv"
    if [ -f "$IPP_PATH/lib/intel64/ippicvmt.lib" ]; then
        log_info "Found IPP ICV (.lib), converting for MinGW..."
        cp "$IPP_PATH/lib/intel64/ippicvmt.lib" "$IPP_PATH/lib/intel64/libippicv.a"
        mv "$IPP_PATH/lib/intel64/ippicvmt.lib" "${INSTALL_ROOT}/lib/libippicv.a"
        log_info "Copying IPP ICV headers to include directory..."
        cp "$IPP_PATH/include"/*.h "${INSTALL_ROOT}/include/"
    else
        log_warn "IPP ICV files not found at $IPP_PATH"
    fi

    # IPP IW PATCH
    local IPP_IW_FILE="3rdparty/ippicv/ippicv_win/iw/src/iw_own.cpp"
    if [ -f "$IPP_IW_FILE" ]; then
        log_info "Surgically removing SEH from IPP IW ($IPP_IW_FILE)..."

        # Force the file to use standard C++ try/catch instead of MSVC __try
        # We do this by undefining ICV_BASE or just nuking the macro definitions
        sed -i 's/#define OWN_TRY   __try/#define OWN_TRY   try/g' "$IPP_IW_FILE"
        sed -i 's/#define OWN_CATCH __except (EXCEPTION_EXECUTE_HANDLER)/#define OWN_CATCH catch (...)/g' "$IPP_IW_FILE"

        # Safety fallback for any direct usages
        sed -i 's/__try/try/g' "$IPP_IW_FILE"
        sed -i 's/__except(EXCEPTION_EXECUTE_HANDLER)/catch(...)/g' "$IPP_IW_FILE"
        sed -i 's/__except(1)/catch(...)/g' "$IPP_IW_FILE"
    else
        log_warn "IPP IW file not found at $IPP_IW_FILE, skipping patch."
    fi

    if [[ "${myconf[@]}" =~ "-DWITH_OPENVINO=ON" ]]; then
        if ! grep -qiE "OPENVINO:.*(YES|ON|TRUE)" CMakeCache.txt && ! grep -qi "HAVE_OPENVINO:INTERNAL=ON" CMakeCache.txt; then
            log_error "OpenVINO was not detected in CMakeCache.txt!"
            grep -i "OPENVINO" CMakeCache.txt # print out for debugging what's actually there
            return 1
        fi
    fi

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local SRC_3RDPARTY="${INSTALL_ROOT}/lib/opencv4/3rdparty"
    local DEST_LIB="${INSTALL_ROOT}/lib"
    local PC_FILE="$PC_DIR/opencv4.pc"

    if [ -d "$SRC_3RDPARTY" ]; then
        log_info "Moving OpenCV 3rdparty libs to main lib directory..."
        mv ${OP_VERB} "$SRC_3RDPARTY"/*.${lib_ext} "$DEST_LIB/" 2>/dev/null || true
        log_info "Searching for IPP ICV library..."
        find . -name "libippicv*.${lib_ext}" -exec cp ${OP_VERB} {} "${DEST_LIB}/" \; || true
        rm -rf "${INSTALL_ROOT}/lib/opencv4"
    fi

    # fix liblib names -> lib
    pushd "${DEST_LIB}" || return 1

    shopt -s nullglob

    for f in liblib*.a; do
        if [ -f "$f" ]; then
            newname=$(echo "$f" | sed 's/^liblib/lib/')
            log_info "Renaming $f to $newname"
            mv -f "$f" "$newname"
        fi
    done

    # Create libopencv_core.a from libopencv_core4140.a
    for lib in libopencv_*.${lib_ext}; do
        unversioned=$(echo "$lib" | sed -E "s/[0-9]+\.${lib_ext}$/.${lib_ext}/" )
        if [ "$lib" != "$unversioned" ]; then
            log_info "Creating symlink $unversioned -> $lib"
            ln -sf "$lib" "$unversioned"
        fi
    done

    shopt -u nullglob
    popd

    # Remove system duplicates if they came from OpenCV 3rd party
    for duplicate in libpng.${lib_ext} libprotobuf.${lib_ext} libz.${lib_ext} libjpeg.${lib_ext} libtiff.${lib_ext} libquirc.${lib_ext}; do
        if [ -f "${FFBUILD_PREFIX}/lib/${duplicate}" ] && [ -f "${DEST_LIB}/${duplicate}" ]; then
             log_info "Removing duplicate ${duplicate} from OpenCV build"
             rm -f "${DEST_LIB}/${duplicate}"
        fi
    done

    # find what is actually built in this mess
    if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
        find /build/$STAGENAME -type f -name "*.${lib_ext}" -printf "%p (%s bytes)\n"
    fi

    # Correcting paths to 3rdparty libraries in OpenCV .cmake configs
    # Replacing the relative path 'lib/opencv4/3rdparty' with just 'lib'
    # Correcting library names from liblib -> lib
    if [ -d "${DEST_LIB}/cmake/opencv4" ]; then
        log_info "Fixing paths and names in .cmake files..."
        find "${DEST_LIB}/cmake/opencv4" -name "*.cmake" -exec sed -i \
            -e 's|lib/opencv4/3rdparty/|lib/|g' \
            -e 's|liblib|lib|g' {} +
    fi

    # Create a symlink so that the header files are located in the standard path
    # ln -sfn opencv4/opencv2 "${INSTALL_ROOT}/include/opencv2"

    log_info "Creating MSVC security cookie stubs for IPP..."
    # Create a stub source code
    cat <<EOF > msvc_stub.c
#include <stdint.h>
#include <stdlib.h>

uintptr_t __security_cookie = 0xBB40E64E;
void __fastcall __security_check_cookie(uintptr_t _StackCookie) {
    if (_StackCookie != __security_cookie) abort();
}

int _fltused = 0;

void __chkstk(void) {
    extern void ___chkstk_ms(void);
    ___chkstk_ms();
}

long long _time64(long long* t) { 
    if (t) *t = 0;
    return 0; 
} 
EOF

    # compile it into an object file and package it into a static library
    ${CC} $CFLAGS -c msvc_stub.c -o msvc_stub.o
    ${AR} rcs "${DEST_LIB}/libmsvc_stub.${lib_ext}" msvc_stub.o

    if [ -f "$PC_FILE" ]; then
        log_info "Fixing includedir path in opencv4.pc..."
        sed -i "s|^includedir=.*|includedir=\${prefix}/include/opencv4|g" "$PC_FILE"
        log_info "Cleaning up OpenCV pkg-config file..."
        # extract the version for the regular expression (dynamically)
        local OPENCV_VER_SUFFIX=$(find "${DEST_LIB}" -name "libopencv_core*.${lib_ext}" | grep -oE "[0-9]+.${lib_ext}$" | sed "s/.${lib_ext}//")
        # move all OpenCV modules from Libs.private to the main Libs
        local ACTUAL_LIBS=$(find "${DEST_LIB}" -name "libopencv_*.${lib_ext}" -printf "%f\n" | sed "s/^lib//;s/\.${lib_ext}$//" | xargs -I{} echo -l{} | tr '\n' ' ')
        # remove the path to 3rdparty, since the libraries moved to the root
        sed -i 's|-L${exec_prefix}/lib/opencv4/3rdparty||g' "$PC_FILE"
        sed -i "s/Requires.private:.*/Requires.private: /" "$PC_FILE"
        # generating a clean Libs string
        local OLD_PRIVATES=$(grep "Libs.private:" "$PC_FILE" | cut -d':' -f2-)
        # Remove any references to -lopencv_* from the current file to avoid duplicates
        # Clean up dependencies: liblib -> lib, absolute paths, garbage
        local CLEAN_PRIVATES=$(echo "$OLD_PRIVATES" | sed -E "s/-llib/-l/g; s|-L/[^ ]*||g; s/-lRunTmChk.${lib_ext}//g; s/-lntdll.${lib_ext}//g; s/-lopencv_[^ ]*//g")
        # Write to file
        sed -i "s|^Libs:.*|Libs: -L\${libdir} ${ACTUAL_LIBS}|" "$PC_FILE"
        sed -i "s|^Libs.private:.*|Libs.private: ${CLEAN_PRIVATES}|" "$PC_FILE"
        # Add the necessary libraries
        if [[ "${myconf[@]}" =~ "-DWITH_OPENVINO=ON" ]]; then
            # sed -i '/^Libs.private:/ s/$/ -lopenvino/' "$PC_FILE"
            sed -i "s|^Requires.private:.*|Requires.private: openvino|" "$PC_FILE"
        fi
        if [[ "${myconf[@]}" =~ "-DWITH_TBB=ON" ]]; then
            sed -i '/^Libs.private:/ s/$/ -ltbb/' "$PC_FILE"
        fi
        if [[ "${myconf[@]}" =~ "-DWITH_IPP=ON" ]]; then
            sed -i 's|^Libs.private: |Libs.private: -lmsvc_stub -lippicv |' "$PC_FILE"
            sed -i 's/-lippicvmt//g; s/-lippicv -lippicv/-lippicv/g' "$PC_FILE"
        fi
        # Removing extra spaces
        sed -i 's/[[:space:]]\+/ /g' "$PC_FILE"
    fi

    if has_library "tiff"; then
        log_info "Explicitly restoring TIFF CMake files before successful exit..."
        restore # Call the recovery function manually

        # Reset the trap so it doesn't execute again
        trap - EXIT

        # File restore check block
        if [ -d "$FFBUILD_PREFIX/lib/cmake/tiff" ]; then
            log_info "Verification: $FFBUILD_PREFIX/lib/cmake/tiff directory exists."
            if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
                log_info "Content of TIFF CMake directory:"
                ls -lh "$FFBUILD_PREFIX/lib/cmake/tiff/"
            fi
        else
            log_warn "Verification failed: $FFBUILD_PREFIX/lib/cmake/tiff directory was NOT restored!"
        fi
    fi

    return 0
}

ffbuild_configure() {
    echo --enable-libopencv
}

ffbuild_unconfigure() {
    echo --disable-libopencv
}
