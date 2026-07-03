set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_SYSTEM_VERSION 10.0)

set(triple x86_64-w64-mingw32)

# set(CMAKE_SYSROOT /opt/ct-ng/${triple}/sysroot/usr/${triple})
# set(CMAKE_FIND_ROOT_PATH /opt/ct-ng ${CMAKE_SYSROOT} /opt/ffbuild)

set(CMAKE_SYSROOT /opt/ct-ng/${triple}/sysroot)
# Сначала ищем в нашем префиксе сборки, потом в системном MinGW
set(CMAKE_FIND_ROOT_PATH /opt/ffbuild /opt/ct-ng/${triple}/sysroot /opt/ct-ng)

# /opt/ct-ng/x86_64-w64-mingw32/sysroot
# /opt/ct-ng/x86_64-w64-mingw32/x86_64-w64-mingw32/sysroot

set(CMAKE_C_COMPILER ${triple}-gcc)
set(CMAKE_CXX_COMPILER ${triple}-g++)
set(CMAKE_RC_COMPILER ${triple}-windres)
set(CMAKE_RANLIB ${triple}-ranlib)
set(CMAKE_AR ${triple}-ar)

# =============================================================================
# LINKER CONFIGURATION (Forcing LLVM LLD for MinGW Target)
# =============================================================================
# Принудительно передаем GCC флаг для вызова LLD на этапе тестов и сборки CMake
set(CMAKE_EXE_LINKER_FLAGS_INIT    "-fuse-ld=lld")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=lld")

# Задаем тип линкера, чтобы CMake правильно понимал его возможности
set(CMAKE_LINKER "ld.lld" CACHE FILEPATH "Forced LLD Linker")

# Искать программы (типа bison) на хосте, а либы и инклюды только в таргете
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Принуждаем pkg-config игнорировать системные пути Linux и искать только в нашем префиксе
set(ENV{PKG_CONFIG_SYSROOT_DIR} "/")
set(ENV{PKG_CONFIG_PATH} "") # Очищаем, чтобы не было мусора
set(ENV{PKG_CONFIG_LIBDIR} "/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig:/opt/ffbuild/lib64/pkgconfig")

set(PKG_CONFIG_ARGN "--static")

if(NOT DEFINED CMAKE_INSTALL_PREFIX)
    set(CMAKE_INSTALL_PREFIX "$ENV{FFBUILD_DESTPREFIX}" CACHE PATH "")
endif()

set(CMAKE_WARN_DEPRECATED OFF CACHE BOOL "" FORCE)

# =============================================================================
# GLOBAL VISIBILITY OVERRIDE (Forcing static links transparency)
# =============================================================================

# форсируем дефолтную (видимую) видимость символов в кэше
# set(CMAKE_C_VISIBILITY_PRESET "default" CACHE INTERNAL "Global override" FORCE)
# set(CMAKE_CXX_VISIBILITY_PRESET "default" CACHE INTERNAL "Global override" FORCE)
# set(CMAKE_VISIBILITY_INLINES_HIDDEN 0 CACHE INTERNAL "Global override" FORCE)

# Защита от переопределения свойств конкретных таргетов (set_target_properties)
# CMake позволяет задать глобальное поведение для всех создаваемых таргетов по умолчанию
# set(CMAKE_C_VISIBILITY_PRESET_INIT "default")
# set(CMAKE_CXX_VISIBILITY_PRESET_INIT "default")
# set(CMAKE_VISIBILITY_INLINES_HIDDEN_INIT 0)

# set(CMAKE_STATIC_LIBRARY_CXX_FLAGS "${CMAKE_STATIC_LIBRARY_CXX_FLAGS} -fvisibility=default")
# set(CMAKE_STATIC_LIBRARY_C_FLAGS "${CMAKE_STATIC_LIBRARY_C_FLAGS} -fvisibility=default")
