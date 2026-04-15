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
set(CMAKE_RANLIB ${triple}-gcc-ranlib)
set(CMAKE_AR ${triple}-gcc-ar)

# Искать программы (типа bison) на хосте, а либы и инклюды только в таргете
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Указываем путь к исполняемому pkg-config (используем хостовый)
set(PKG_CONFIG_EXECUTABLE "/usr/bin/pkg-config" CACHE FILEPATH "pkg-config executable")
find_program(PKG_CONFIG_EXECUTABLE NAMES pkg-config)

# Принуждаем pkg-config игнорировать системные пути Linux и искать только в нашем префиксе
set(ENV{PKG_CONFIG_SYSROOT_DIR} "/")
set(ENV{PKG_CONFIG_PATH} "") # Очищаем, чтобы не было мусора
set(ENV{PKG_CONFIG_LIBDIR} "/opt/ffbuild/lib/pkgconfig")

if(NOT DEFINED CMAKE_INSTALL_PREFIX)
    set(CMAKE_INSTALL_PREFIX "$ENV{FFBUILD_DESTPREFIX}" CACHE PATH "")
endif()