#!/bin/bash

SCRIPT_REPO="https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-python-pytorch-2.12.0-4-any.pkg.tar.zst"

# collecting satellite DLLs
GCC_LINK="https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-gcc-libs-16.1.0-5-any.pkg.tar.zst"
GLOG_LINK="https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-glog-0.7.1-10-any.pkg.tar.zst"
SLEEF_LINK="https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-sleef-3.9.0-2-any.pkg.tar.zst"
OPENBLAS_LINK="https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-openblas-0.3.33-3-any.pkg.tar.zst"
PROTOBUF_LINK="https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-protobuf-35.0-1-any.pkg.tar.zst"
UNWIND_LINK="https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-libunwind-22.1.7-1-any.pkg.tar.zst"
ABSEIL_LINK="https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-abseil-cpp-20260526.0-1-any.pkg.tar.zst"
VULKAN_LINK="https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-vulkan-loader-1~1.4.350.0-1-any.pkg.tar.zst"
ZLIB_LINK="https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-zlib-1.3.2-2-any.pkg.tar.zst"
FORTRAN_LINK="https://repo.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-gcc-libgfortran-16.1.0-5-any.pkg.tar.zst"

ffbuild_enabled() {
# C++ runtime version conflict (libstdc++-6.dll) between the cross-compiler and the binary package
# Symbol _ZSt15__get_once_callv (std::__get_once_call()) is a symbol in the C++ standard library (libstdc++) for the implementation of std::call_once
    [[ "$USE_LIBTORCH" == "1" ]] && return 0
    return 1
}

ffbuild_dockerdl() {
    cat << EOF
    download_file "$SCRIPT_REPO" "pytorch.tar.zst"
    mkdir -p extracted
    tar --use-compress-program=unzstd -xf pytorch.tar.zst -C extracted/ --wildcards "*/site-packages/torch/include*" "*/site-packages/torch/lib*"
    mv extracted/ucrt64/lib/python*/site-packages/torch/include .
    mv extracted/ucrt64/lib/python*/site-packages/torch/lib .
    rm -rf pytorch.tar.zst extracted

    # --- GCC LIBS ---
    download_file "$GCC_LINK" "gcc-libs.tar.zst"
    mkdir -p ext_gcclibs
    tar --use-compress-program=unzstd -xf gcc-libs.tar.zst -C ext_gcclibs/ --wildcards "*/bin/*.dll"
    cp -f${OP_V} ext_gcclibs/ucrt64/bin/*.dll lib/
    rm -rf gcc-libs.tar.zst ext_gcclibs

    # --- GOOGLE LOG ---
    download_file "$GLOG_LINK" "glog.tar.zst"
    mkdir -p extracted_glog
    tar --use-compress-program=unzstd -xf glog.tar.zst -C extracted_glog/ --wildcards "*/include/glog*" "*/lib/*.a" "*/bin/*.dll"
    mkdir -p include/glog lib
    cp -rf extracted_glog/ucrt64/include/glog/* include/glog/
    cp -f${OP_V} extracted_glog/ucrt64/lib/libglog.dll.a lib/glog.dll.a
    cp -f${OP_V} extracted_glog/ucrt64/bin/libglog-*.dll lib/
    rm -rf glog.tar.zst extracted_glog

    # --- SLEEF ---
    download_file "$SLEEF_LINK" "sleef.tar.zst"
    mkdir -p ext_sleef
    tar --use-compress-program=unzstd -xf sleef.tar.zst -C ext_sleef/ --wildcards "*/bin/*.dll"
    cp -f${OP_V} ext_sleef/ucrt64/bin/*.dll lib/
    rm -rf sleef.tar.zst ext_sleef

    # --- OPENBLAS ---
    download_file "$OPENBLAS_LINK" "openblas.tar.zst"
    mkdir -p ext_openblas
    tar --use-compress-program=unzstd -xf openblas.tar.zst -C ext_openblas/ --wildcards "*/bin/*.dll"
    cp -f${OP_V} ext_openblas/ucrt64/bin/*.dll lib/
    rm -rf openblas.tar.zst ext_openblas

    # --- PROTOBUF ---
    download_file "$PROTOBUF_LINK" "protobuf.tar.zst"
    mkdir -p ext_protobuf
    tar --use-compress-program=unzstd -xf protobuf.tar.zst -C ext_protobuf/ --wildcards "*/bin/*.dll"
    cp -f${OP_V} ext_protobuf/ucrt64/bin/*.dll lib/
    rm -rf protobuf.tar.zst ext_protobuf

    # --- LIBUNWIND ---
    download_file "$UNWIND_LINK" "unwind.tar.zst"
    mkdir -p ext_unwind
    tar --use-compress-program=unzstd -xf unwind.tar.zst -C ext_unwind/ --wildcards "*/bin/*.dll"
    cp -f${OP_V} ext_unwind/ucrt64/bin/*.dll lib/
    rm -rf unwind.tar.zst ext_unwind

    # --- ABSL ---
    download_file "$ABSEIL_LINK" "abseil.tar.zst"
    mkdir -p ext_abseil
    tar --use-compress-program=unzstd -xf abseil.tar.zst -C ext_abseil/ --wildcards "*/bin/libabsl_*.dll"
    cp -f${OP_V} ext_abseil/ucrt64/bin/*.dll lib/
    rm -rf abseil.tar.zst ext_abseil

    # --- VULKAN ---
    download_file "$VULKAN_LINK" "vulkan.tar.zst"
    mkdir -p ext_vulkan
    tar --use-compress-program=unzstd -xf vulkan.tar.zst -C ext_vulkan/ --wildcards "*/bin/*.dll"
    cp -f${OP_V} ext_vulkan/ucrt64/bin/vulkan-*.dll lib/
    rm -rf vulkan.tar.zst ext_vulkan

    # --- ZLIB ---
    download_file "$ZLIB_LINK" "zlib.tar.zst"
    mkdir -p ext_zlib
    tar --use-compress-program=unzstd -xf zlib.tar.zst -C ext_zlib/ --wildcards "*/bin/*.dll"
    cp -f${OP_V} ext_zlib/ucrt64/bin/zlib*.dll lib/
    rm -rf zlib.tar.zst ext_zlib

    # --- FORTRAN ---
    download_file "$FORTRAN_LINK" "fortran.tar.zst"
    mkdir -p ext_fortran
    tar --use-compress-program=unzstd -xf fortran.tar.zst -C ext_fortran/ --wildcards "*/bin/*.dll"
    cp -f${OP_V} ext_fortran/ucrt64/bin/libgfortran*.dll lib/
    rm -rf fortran.tar.zst ext_fortran

    log_info "Filtering and cleaning up unused MSYS2 DLLs via LDD wildcard mask..."
    mkdir -p lib_cleaned

    local whitelist=(
        "libabsl_base-*.dll" "libabsl_city-*.dll" "libabsl_cord-*.dll"
        "libabsl_cord_internal-*.dll" "libabsl_cordz_handle-*.dll" "libabsl_cordz_info-*.dll"
        "libabsl_crc32c-*.dll" "libabsl_crc_cord_state-*.dll" "libabsl_crc_internal-*.dll"
        "libabsl_die_if_null-*.dll" "libabsl_examine_stack-*.dll" "libabsl_hash-*.dll"
        "libabsl_hashtablez_sampler-*.dll" "libabsl_int128-*.dll" "libabsl_kernel_timeout_internal-*.dll"
        "libabsl_leak_check-*.dll" "libabsl_log_globals-*.dll" "libabsl_log_internal_check_op-*.dll"
        "libabsl_log_internal_conditions-*.dll" "libabsl_log_internal_format-*.dll" "libabsl_log_internal_globals-*.dll"
        "libabsl_log_internal_log_sink_set-*.dll" "libabsl_log_internal_message-*.dll" "libabsl_log_internal_nullguard-*.dll"
        "libabsl_log_internal_proto-*.dll" "libabsl_log_internal_structured_proto-*.dll" "libabsl_log_sink-*.dll"
        "libabsl_malloc_internal-*.dll" "libabsl_raw_hash_set-*.dll" "libabsl_raw_logging_internal-*.dll"
        "libabsl_spinlock_wait-*.dll" "libabsl_stacktrace-*.dll" "libabsl_status-*.dll"
        "libabsl_statusor-*.dll" "libabsl_str_format_internal-*.dll" "libabsl_strerror-*.dll"
        "libabsl_strings-*.dll" "libabsl_strings_internal-*.dll" "libabsl_symbolize-*.dll"
        "libabsl_synchronization-*.dll" "libabsl_throw_delegate-*.dll" "libabsl_time-*.dll"
        "libabsl_time_zone-*.dll" "libabsl_tracing_internal-*.dll" "libc*.dll"
        "libgcc_s_*.dll" "libgfortran*.dll" "libglog*.dll" "libgomp*.dll"
        "libopenblas*.dll" "libprotobuf*.dll" "libquadmath*.dll" "libsleef*.dll"
        "libstdc++*.dll" "libtorch_cpu*.dll" "libtorch.dll" "libunwind*.dll" "libutf8_validity*.dll"
        "libwinpthread*.dll" "vulkan*.dll" "zlib*.dll"
    )

    for mask in "\${whitelist[@]}"; do
        for f in lib/\$mask; do
            if [[ -f "\$f" ]]; then
                cp -f "\$f" lib_cleaned/
            fi
        done
    done

    cp -f lib/*.dll.a lib_cleaned/ 2>/dev/null || true
    rm -rf lib
    mv -f lib_cleaned lib
EOF
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p "${INSTALL_ROOT}"/{include,lib,bin}

    log_info "Preparing LibTorch headers for GCC 15 compatibility..."

    # Прописываем базовые типы в заголовки C10/Torch, чтобы GCC 15 не падал на uint64_t или std::string
    find include/ -name "*.h" -o -name "*.hpp" -exec sed -i '1i #include <cstdint>\n#include <string>\n#include <stdexcept>' {} + 2>/dev/null || true

    # Решение abi/api конфликта glog
    # Создаем преамбулу, которая активирует родной export.h и отключает опасные макросы
    if [[ -d "include/glog" ]]; then
        log_info "Injecting official macro triggers into glog master headers..."

        cat << 'EOF' > include/glog/ffmpeg_glog_fix.h
#ifndef FFMPEG_GLOG_FIX_H_
#define FFMPEG_GLOG_FIX_H_

#ifndef GLOG_NO_ABBREVIATED_SEVERITIES
#define GLOG_NO_ABBREVIATED_SEVERITIES
#endif

#ifndef GLOG_USE_GLOG_EXPORT
#define GLOG_USE_GLOG_EXPORT
#endif

#endif // FFMPEG_GLOG_FIX_H_
EOF

        # Инжектируем преамбулу первой строкой во ВСЕ заголовки glog
        find include/glog/ -name "*.h" ! -name "ffmpeg_glog_fix.h" -exec sed -i '1i #include "ffmpeg_glog_fix.h"' {} +
    fi

    # Раскладываем заголовочные файлы
    cp -rf include/* "${INSTALL_ROOT}/include/"

    log_info "Distributing LibTorch and glog libraries..."
    # Копируем динамические .dll (они уйдут в финальный дистрибутив ffmpeg)
    cp -f${OP_V} lib/*.dll "${INSTALL_ROOT}/bin/" 2>/dev/null || true

    # Копируем библиотеки импорта. 
    # В MSYS2 они называются *.dll.a, копируем их с переименованием в lib*.a
    for libfile in lib/*.dll.a; do
        if [[ -f "$libfile" ]]; then
            local filename=$(basename "$libfile")
            local clean_name=$(echo "$filename" | sed 's/\.dll\.a$//')
            if [[ "$clean_name" == lib* ]]; then
                cp -f${OP_V} "$libfile" "${INSTALL_ROOT}/lib/${clean_name}.a"
            else
                cp -f${OP_V} "$libfile" "${INSTALL_ROOT}/lib/lib${clean_name}.a"
            fi
        fi
    done

    # делаем копию libglog.a, чтобы линкер понимал как -lglog, так и -lglog-2
    if [[ -f "${INSTALL_ROOT}/lib/libglog.a" ]]; then
        cp -f${OP_V} "${INSTALL_ROOT}/lib/libglog.a" "${INSTALL_ROOT}/lib/libglog-2.a"
    elif [[ -f "${INSTALL_ROOT}/lib/libglog-2.a" ]]; then
        cp -f${OP_V} "${INSTALL_ROOT}/lib/libglog-2.a" "${INSTALL_ROOT}/lib/libglog.a"
    fi

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/libtorch.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: LibTorch
Description: PyTorch C++ API (MSYS2 MinGW-w64 Build)
Version: 2.12.0
Libs: -L\${libdir} -ltorch -ltorch_cpu -lc10 -lglog -lopenblas -lprotobuf -lsleef-3 -lunwind -labsl_cord-2605.0.0
Libs.private: -lshlwapi -lws2_32 -lstdc++ -lpthread
Cflags: -I\${includedir} -I\${includedir}/torch/csrc/api/include -DNOMINMAX -DNDEBUG -DGLOG_NO_ABBREVIATED_SEVERITIES
EOF
}

ffbuild_cxxflags() {
    echo "-Wno-deprecated-declarations -Wno-error=deprecated-declarations -fpermissive -I$FFBUILD_PREFIX/include/torch/csrc/api/include -I$FFBUILD_PREFIX/include/torch/csrc/jit -DNOMINMAX -DNDEBUG -DGLOG_NO_ABBREVIATED_SEVERITIES"
}

ffbuild_configure() {
    echo --enable-libtorch
}

ffbuild_unconfigure() {
    echo --disable-libtorch
}
