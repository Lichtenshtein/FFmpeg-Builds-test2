set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_SYSTEM_VERSION 10.0)

set(triple x86_64-w64-mingw32)

# set(CMAKE_SYSROOT /opt/ct-ng/${triple}/sysroot)
# Путь должен вести к папке с usr/include и usr/lib внутри ct-ng
set(CMAKE_SYSROOT /opt/ct-ng/${triple}/${triple}/sysroot)

# set(CMAKE_FIND_ROOT_PATH /opt/ct-ng /opt/ct-ng/${triple}/sysroot /opt/ffbuild)
# Позволяем CMake искать пакеты в префиксе ПЕРВЫМ делом
set(CMAKE_FIND_ROOT_PATH /opt/ffbuild ${CMAKE_SYSROOT})

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

# Полезные флаги для статики
set(CMAKE_C_FLAGS_INIT "-I/opt/ffbuild/include -D_WIN32_WINNT=0x0A00")
set(CMAKE_CXX_FLAGS_INIT "-I/opt/ffbuild/include -D_WIN32_WINNT=0x0A00")
