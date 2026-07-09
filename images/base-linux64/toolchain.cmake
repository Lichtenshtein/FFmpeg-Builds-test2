set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_SYSTEM_VERSION 4.18.20)

set(triple x86_64-ffbuild-linux-gnu)

set(CMAKE_C_COMPILER ${triple}-gcc)
set(CMAKE_CXX_COMPILER ${triple}-g++)
set(CMAKE_RANLIB ${triple}-gcc-ranlib)
set(CMAKE_AR ${triple}-gcc-ar)

set(CMAKE_SYSROOT /opt/ct-ng/${triple}/sysroot)
set(CMAKE_FIND_ROOT_PATH /opt/ct-ng /opt/ct-ng/${triple}/sysroot /opt/ffbuild)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

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
