cmake_minimum_required(VERSION 3.10)
if(POLICY CMP0083)
  cmake_policy(SET CMP0083 NEW)
endif()
if(POLICY CMP0111)
  cmake_policy(SET CMP0111 OLD)
endif()
if(POLICY CMP0128)
  cmake_policy(SET CMP0128 NEW)
endif()
project(hwy VERSION 1.2.0)
set(namespace "${PROJECT_NAME}::")
set(LIBRARY_VERSION "${hwy_VERSION}")
set(LIBRARY_SOVERSION ${hwy_VERSION_MAJOR})
set(CMAKE_CXX_EXTENSIONS OFF)
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
find_package(Atomics REQUIRED)
include(CheckPIESupported OPTIONAL RESULT_VARIABLE CHECK_PIE_SUPPORTED)
if(CHECK_PIE_SUPPORTED)
  check_pie_supported(LANGUAGES CXX)
  if(CMAKE_CXX_LINK_PIE_SUPPORTED)
	set(CMAKE_POSITION_INDEPENDENT_CODE TRUE)
  endif()
endif()
include(GNUInstallDirs)
if (NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()
set(HWY_CMAKE_ARM7 OFF CACHE BOOL "Set copts for Armv7 with NEON (requires vfpv4)?")
set(HWY_CMAKE_SSE2 OFF CACHE BOOL "Set SSE2 as baseline for 32-bit x86?")
set(HWY_CMAKE_RVV ON CACHE BOOL "Set copts for RISCV with RVV?")
set(HWY_WARNINGS_ARE_ERRORS OFF CACHE BOOL "Add -Werror flag?")
set(HWY_CMAKE_HEADER_ONLY OFF CACHE BOOL "Change to header-only?")
set(HWY_ENABLE_CONTRIB ON CACHE BOOL "Include contrib/")
set(HWY_ENABLE_EXAMPLES ON CACHE BOOL "Build examples")
set(HWY_ENABLE_INSTALL ON CACHE BOOL "Install library")

if (NOT DEFINED CMAKE_CXX_STANDARD)
  if ("cxx_std_17" IN_LIST CMAKE_CXX_COMPILE_FEATURES)
	set(HWY_CXX_STD_TGT_COMPILE_FEATURE cxx_std_17)
  else()
	if ("cxx_std_14" IN_LIST CMAKE_CXX_COMPILE_FEATURES)
	  set(HWY_CXX_STD_TGT_COMPILE_FEATURE cxx_std_14)
	else()
	  set(HWY_CXX_STD_TGT_COMPILE_FEATURE cxx_std_11)
	endif()
  endif()
else()
  if (CMAKE_CXX_STANDARD GREATER_EQUAL 14 AND CMAKE_CXX_STANDARD LESS 98)
	if (CMAKE_CXX_STANDARD GREATER_EQUAL 17)
	  set(HWY_CXX_STD_TGT_COMPILE_FEATURE cxx_std_17)
	else()
	  set(HWY_CXX_STD_TGT_COMPILE_FEATURE cxx_std_14)
	endif()
  else()
	set(HWY_CXX_STD_TGT_COMPILE_FEATURE cxx_std_11)
  endif()
endif()
include(CheckCXXSourceCompiles)
check_cxx_source_compiles(
   "int main() {
	  #if !defined(__EMSCRIPTEN__)
	  static_assert(false, \"__EMSCRIPTEN__ is not defined\");
	  #endif
	  return 0;
	}"
  HWY_EMSCRIPTEN
)
check_cxx_source_compiles(
   "int main() {
	  #if !defined(__riscv)
	  static_assert(false, \"__riscv is not defined\");
	  #endif
	  return 0;
	}"
  HWY_RISCV
)
if (HWY_ENABLE_CONTRIB)
file(GLOB HWY_CONTRIB_SOURCES "hwy/contrib/sort/vqsort_*.cc")
list(APPEND HWY_CONTRIB_SOURCES
	hwy/contrib/bit_pack/bit_pack-inl.h
	hwy/contrib/dot/dot-inl.h
	hwy/contrib/image/image.cc
	hwy/contrib/image/image.h
	hwy/contrib/math/math-inl.h
	hwy/contrib/matvec/matvec-inl.h
	hwy/contrib/random/random-inl.h
	hwy/contrib/sort/order.h
	hwy/contrib/sort/shared-inl.h
	hwy/contrib/sort/sorting_networks-inl.h
	hwy/contrib/sort/traits-inl.h
	hwy/contrib/sort/traits128-inl.h
	hwy/contrib/sort/vqsort-inl.h
	hwy/contrib/sort/vqsort.cc
	hwy/contrib/sort/vqsort.h
	hwy/contrib/thread_pool/futex.h
	hwy/contrib/thread_pool/thread_pool.h
	hwy/contrib/thread_pool/topology.cc
	hwy/contrib/thread_pool/topology.h
	hwy/contrib/algo/copy-inl.h
	hwy/contrib/algo/find-inl.h
	hwy/contrib/algo/transform-inl.h
	hwy/contrib/unroller/unroller-inl.h
)
endif()
set(HWY_SOURCES
	hwy/abort.h
	hwy/aligned_allocator.h
	hwy/base.h
	hwy/cache_control.h
	hwy/detect_compiler_arch.h
	hwy/detect_targets.h
	hwy/foreach_target.h
	hwy/highway_export.h
	hwy/highway.h
	hwy/nanobenchmark.h
	hwy/ops/arm_neon-inl.h
	hwy/ops/arm_sve-inl.h
	hwy/ops/emu128-inl.h
	hwy/ops/generic_ops-inl.h
	hwy/ops/inside-inl.h
	hwy/ops/ppc_vsx-inl.h
	hwy/ops/rvv-inl.h
	hwy/ops/scalar-inl.h
	hwy/ops/set_macros-inl.h
	hwy/ops/shared-inl.h
	hwy/ops/wasm_128-inl.h
	hwy/ops/x86_128-inl.h
	hwy/ops/x86_256-inl.h
	hwy/ops/x86_512-inl.h
	hwy/per_target.h
	hwy/print-inl.h
	hwy/print.h
	hwy/profiler.h
	hwy/robust_statistics.h
	hwy/targets.h
	hwy/timer-inl.h
	hwy/timer.h
)
if (NOT HWY_CMAKE_HEADER_ONLY)
  list(APPEND HWY_SOURCES
	hwy/abort.cc
	hwy/aligned_allocator.cc
	hwy/nanobenchmark.cc
	hwy/per_target.cc
	hwy/print.cc
	hwy/targets.cc
	hwy/timer.cc
  )
endif()
if (MSVC)
  set(HWY_FLAGS
	/bigobj
	/W4
	/wd4100
	/wd4127
	/wd4324
	/wd4456
	/wd4701
	/wd4702
	/wd4723
	/GR-
	/EHs-c-
	-D_HAS_EXCEPTIONS=0
  )
  if (${CMAKE_CXX_COMPILER_ID} MATCHES "Clang")
	list(APPEND HWY_FLAGS
	  -Wconversion
	  -Wsign-conversion
	  -Wvla
	  -Wnon-virtual-dtor
	  -Wfloat-overflow-conversion
	  -Wfloat-zero-conversion
	  -Wfor-loop-analysis
	  -Wgnu-redeclared-enum
	  -Winfinite-recursion
	  -Wself-assign
	  -Wstring-conversion
	  -Wtautological-overlap-compare
	  -Wthread-safety-analysis
	  -Wundefined-func-template
	)
  endif()
  if (HWY_WARNINGS_ARE_ERRORS)
	list(APPEND HWY_FLAGS /WX)
  endif()
else()
  set(HWY_FLAGS
	-Wno-builtin-macro-redefined
	-D__DATE__="redacted"
	-D__TIMESTAMP__="redacted"
	-D__TIME__="redacted"
	-fmerge-all-constants
	-Wall
	-Wextra
	-Wconversion
	-Wsign-conversion
	-Wvla
	-Wnon-virtual-dtor
	-Wcast-align
  )
  if(${CMAKE_CXX_COMPILER_ID} MATCHES "Clang")
	list(APPEND HWY_FLAGS
	  -Wfloat-overflow-conversion
	  -Wfloat-zero-conversion
	  -Wfor-loop-analysis
	  -Wgnu-redeclared-enum
	  -Winfinite-recursion
	  -Wself-assign
	  -Wstring-conversion
	  -Wtautological-overlap-compare
	  -Wthread-safety-analysis
	  -Wundefined-func-template
	  -fno-cxx-exceptions
	  -fno-slp-vectorize
	  -fno-vectorize
	  -fdiagnostics-show-option -fcolor-diagnostics
	)
	if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 6.0)
	  list(APPEND HWY_FLAGS -Wc++2a-extensions)
	endif()
  endif()
  if (WIN32)
	if(${CMAKE_CXX_COMPILER_ID} MATCHES "Clang")
	  list(APPEND HWY_FLAGS
		-Wno-global-constructors
		-Wno-language-extension-token
		-Wno-used-but-marked-unused
		-Wno-shadow-field-in-constructor
		-Wno-unused-member-function
		-Wno-unused-template
		-Wno-c++98-compat-pedantic
		-Wno-used-but-marked-unused
		-Wno-zero-as-null-pointer-constant
	  )
	endif()
	list(APPEND HWY_FLAGS
	  -Wno-cast-align
	  -Wno-double-promotion
	  -Wno-float-equal
	  -Wno-format-nonliteral
	  -Wno-shadow
	  -Wno-sign-conversion
	)
  else()
	list(APPEND HWY_FLAGS
	  -fmath-errno
	  -fno-exceptions
	)
  endif()
  if (HWY_CMAKE_SSE2)
	list(APPEND HWY_FLAGS -msse2 -mfpmath=sse)
  endif()
  if (${CMAKE_CXX_COMPILER_ID} MATCHES "GNU")
	list(APPEND HWY_FLAGS -Wno-psabi)
  endif()
  if (${CMAKE_CXX_COMPILER_ID} MATCHES "Clang")
	if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 11.0)
	  list(APPEND HWY_FLAGS -Wno-psabi)
	endif()
  endif()
  if (HWY_CMAKE_ARM7)
	list(APPEND HWY_FLAGS
	  -march=armv7-a
	  -mfpu=neon-vfpv4
	  -mfloat-abi=hard
	)
	if(${CMAKE_CXX_COMPILER_ID} MATCHES "GNU")
	  list(APPEND HWY_FLAGS
		-mfp16-format=ieee
	  )
	endif()
  endif()
  if(HWY_RISCV)
	if(HWY_CMAKE_RVV)
	  list(APPEND HWY_FLAGS -march=rv64gcv1p0)
	  if(${CMAKE_CXX_COMPILER_ID} MATCHES "Clang")
		list(APPEND HWY_FLAGS -menable-experimental-extensions)
	  endif()
	endif()
  endif()
  if (HWY_WARNINGS_ARE_ERRORS)
	list(APPEND HWY_FLAGS -Werror)
  endif()
  if (HWY_EMSCRIPTEN)
	list(APPEND HWY_FLAGS -matomics)
  endif()
endif()
if (HWY_CMAKE_HEADER_ONLY)
  list(APPEND HWY_FLAGS -DHWY_HEADER_ONLY)
endif()
include(CheckIncludeFile)
check_include_file(sys/auxv.h  HAVE_SYS_AUXV_H)
check_include_file(asm/hwcap.h HAVE_ASM_HWCAP_H)
option(BUILD_SHARED_LIBS "Build shared libraries" OFF)
option(HWY_FORCE_STATIC_LIBS "Ignore BUILD_SHARED_LIBS" OFF)
mark_as_advanced(BUILD_SHARED_LIBS)
mark_as_advanced(HWY_FORCE_STATIC_LIBS)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN 1)
set(HWY_LIBRARY_TYPE "SHARED")
if (NOT BUILD_SHARED_LIBS OR HWY_FORCE_STATIC_LIBS)
  set(HWY_LIBRARY_TYPE "STATIC")
endif()
if("${HWY_LIBRARY_TYPE}" STREQUAL "SHARED")
  set(DLLEXPORT_TO_DEFINE "HWY_SHARED_DEFINE")
else()
  set(DLLEXPORT_TO_DEFINE "HWY_STATIC_DEFINE")
endif()
add_library(hwy ${HWY_LIBRARY_TYPE} ${HWY_SOURCES})
if(NOT HAVE_SYS_AUXV_H)
  target_compile_definitions(hwy PUBLIC TOOLCHAIN_MISS_SYS_AUXV_H)
endif()
if(NOT HAVE_ASM_HWCAP_H)
  target_compile_definitions(hwy PUBLIC TOOLCHAIN_MISS_ASM_HWCAP_H)
endif()
target_compile_definitions(hwy PUBLIC "${DLLEXPORT_TO_DEFINE}")
target_compile_options(hwy PRIVATE ${HWY_FLAGS})
set_property(TARGET hwy PROPERTY POSITION_INDEPENDENT_CODE ON)
set_target_properties(hwy PROPERTIES VERSION ${LIBRARY_VERSION} SOVERSION ${LIBRARY_SOVERSION})
target_include_directories(hwy PUBLIC
	$<BUILD_INTERFACE:${CMAKE_CURRENT_LIST_DIR}>
	$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>)
target_compile_features(hwy PUBLIC cxx_std_11)
if (NOT HWY_CXX_STD_TGT_COMPILE_FEATURE STREQUAL "cxx_std_11")
  target_compile_features(hwy PRIVATE ${HWY_CXX_STD_TGT_COMPILE_FEATURE})
endif()
set_target_properties(hwy PROPERTIES
  LINK_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/hwy/hwy.version)
target_link_libraries(hwy PRIVATE ${ATOMICS_LIBRARIES})
if(UNIX AND NOT APPLE)
  set_property(TARGET hwy APPEND_STRING PROPERTY
	LINK_FLAGS " -Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/hwy/hwy.version")
endif()
if (HWY_ENABLE_CONTRIB)
add_library(hwy_contrib ${HWY_LIBRARY_TYPE} ${HWY_CONTRIB_SOURCES})
target_link_libraries(hwy_contrib PUBLIC hwy)
target_compile_options(hwy_contrib PRIVATE ${HWY_FLAGS})
set_property(TARGET hwy_contrib PROPERTY POSITION_INDEPENDENT_CODE ON)
set_target_properties(hwy_contrib PROPERTIES VERSION ${LIBRARY_VERSION} SOVERSION ${LIBRARY_SOVERSION})
target_include_directories(hwy_contrib PUBLIC
	$<BUILD_INTERFACE:${CMAKE_CURRENT_LIST_DIR}>
	$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>)
target_compile_features(hwy_contrib PUBLIC cxx_std_11)
if (NOT HWY_CXX_STD_TGT_COMPILE_FEATURE STREQUAL "cxx_std_11")
  target_compile_features(hwy_contrib PRIVATE ${HWY_CXX_STD_TGT_COMPILE_FEATURE})
endif()
set_target_properties(hwy_contrib PROPERTIES
  LINK_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/hwy/hwy.version)
target_link_libraries(hwy_contrib PRIVATE ${ATOMICS_LIBRARIES})
if(UNIX AND NOT APPLE)
  set_property(TARGET hwy_contrib APPEND_STRING PROPERTY
	LINK_FLAGS " -Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/hwy/hwy.version")
endif()
endif()
if (HWY_ENABLE_INSTALL)
install(TARGETS hwy EXPORT hwy_targets
  LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
  ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
foreach (source ${HWY_SOURCES})
  if ("${source}" MATCHES "\.h$")
	get_filename_component(dirname "${source}" DIRECTORY)
	install(FILES "${source}"
		DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/${dirname}")
  endif()
endforeach()
if (HWY_ENABLE_CONTRIB)
install(TARGETS hwy_contrib EXPORT hwy_targets
  LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
  ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
foreach (source ${HWY_CONTRIB_SOURCES})
  if ("${source}" MATCHES "\.h$")
	get_filename_component(dirname "${source}" DIRECTORY)
	install(FILES "${source}"
		DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/${dirname}")
  endif()
endforeach()
endif()
set(HWY_LIBRARY_VERSION "${CMAKE_PROJECT_VERSION}")
set(HWY_PC_FILES libhwy.pc)
if (HWY_ENABLE_CONTRIB)
list(APPEND HWY_PC_FILES libhwy-contrib.pc)
endif()
foreach (pc ${HWY_PC_FILES})
  configure_file("${CMAKE_CURRENT_SOURCE_DIR}/${pc}.in" "${pc}" @ONLY)
  install(FILES "${CMAKE_CURRENT_BINARY_DIR}/${pc}"
	  DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig")
endforeach()
endif()
if (HWY_ENABLE_EXAMPLES)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
add_executable(hwy_benchmark hwy/examples/benchmark.cc)
target_sources(hwy_benchmark PRIVATE
	hwy/nanobenchmark.h)
target_compile_options(hwy_benchmark PRIVATE ${HWY_FLAGS})
target_compile_features(hwy_benchmark PRIVATE ${HWY_CXX_STD_TGT_COMPILE_FEATURE})
target_link_libraries(hwy_benchmark PRIVATE hwy)
target_link_libraries(hwy_benchmark PRIVATE ${ATOMICS_LIBRARIES})
set_target_properties(hwy_benchmark
	PROPERTIES RUNTIME_OUTPUT_DIRECTORY "examples/")
add_executable(hwy_profiler_example hwy/examples/profiler_example.cc)
target_sources(hwy_profiler_example PRIVATE
	hwy/profiler.h)
target_compile_options(hwy_profiler_example PRIVATE ${HWY_FLAGS})
target_compile_features(hwy_profiler_example PRIVATE ${HWY_CXX_STD_TGT_COMPILE_FEATURE})
target_link_libraries(hwy_profiler_example PRIVATE hwy)
target_link_libraries(hwy_profiler_example PRIVATE ${ATOMICS_LIBRARIES})
set_target_properties(hwy_profiler_example
	PROPERTIES RUNTIME_OUTPUT_DIRECTORY "examples/")
endif()
if (HWY_ENABLE_INSTALL)
  include(CMakePackageConfigHelpers)
  write_basic_package_version_file("${CMAKE_CURRENT_BINARY_DIR}/hwy-config-version.cmake" COMPATIBILITY SameMajorVersion)
  install(FILES "${CMAKE_CURRENT_BINARY_DIR}/hwy-config-version.cmake" DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/hwy")
  install(EXPORT hwy_targets NAMESPACE "${namespace}" FILE hwy-config.cmake DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/hwy")
endif()