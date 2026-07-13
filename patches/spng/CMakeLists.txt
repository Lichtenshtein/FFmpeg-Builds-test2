cmake_minimum_required(VERSION 3.12)

project(libspng C)

set(CMAKE_C_STANDARD 99)

set(SPNG_MAJOR 0)
set(SPNG_MINOR 7)
set(SPNG_REVISION 4)
set(SPNG_VERSION ${SPNG_MAJOR}.${SPNG_MINOR}.${SPNG_REVISION})

option(SPNG_ENABLE_OPT "Enable architecture-specific optimizations" ON)
option(SPNG_SHARED "Build shared lib" OFF)
option(SPNG_STATIC "Build static lib" ON)
option(SPNG_INSTALL "Enable install" ON)

unset(SPNG_CUSTOM_ZLIB_TARGET CACHE)
set(SPNG_DEPENDENCIES "")
set(SPNG_USE_MINIZ OFF)

if(SPNG_INSTALL)
    include(GNUInstallDirs)
    include(CMakePackageConfigHelpers)
endif()

if(NOT WIN32)
    set(SPNG_DEPENDENCIES "m")
endif()

if(DEFINED SPNG_CUSTOM_ZLIB_TARGET)
    set(SPNG_DEPENDENCIES ${SPNG_DEPENDENCIES} ${SPNG_CUSTOM_ZLIB_TARGET})
    if(${SPNG_CUSTOM_ZLIB_TARGET} MATCHES "[Mm][Ii][Nn][Ii][Zz]")
        set(SPNG_USE_MINIZ ON)
    endif()
else()
    find_package(ZLIB REQUIRED)
    set(SPNG_DEPENDENCIES ${SPNG_DEPENDENCIES} ZLIB::ZLIB)
endif()

if(NOT SPNG_ENABLE_OPT)
    add_definitions( -DSPNG_DISABLE_OPT=1 )
endif()

set(spng_TARGETS "")
set(spng_SOURCES spng/spng.c)

if(SPNG_SHARED)
    add_library(spng SHARED ${spng_SOURCES})
    set_target_properties(spng PROPERTIES OUTPUT_NAME spng)
    list(APPEND spng_TARGETS spng)
endif()

if(SPNG_STATIC)
    if(NOT SPNG_SHARED)
        add_library(spng STATIC ${spng_SOURCES})
        set_target_properties(spng PROPERTIES OUTPUT_NAME spng)
        list(APPEND spng_TARGETS spng)
        set(SPNG_LIBNAME spng)
    else()
        add_library(spng_static STATIC ${spng_SOURCES})
        set_target_properties(spng_static PROPERTIES OUTPUT_NAME spng_static)
        list(APPEND spng_TARGETS spng_static)
        set(SPNG_LIBNAME spng_static) 
    endif()

    foreach(tgt ${spng_TARGETS})
        if(tgt MATCHES "static")
            target_compile_definitions(${tgt} PUBLIC SPNG_STATIC)
        endif()
    endforeach()
    if(NOT SPNG_SHARED)
        target_compile_definitions(spng PUBLIC SPNG_STATIC)
    endif()
endif()

set(SPKG_LIBNAME spng) 

foreach(spng_TARGET ${spng_TARGETS})
    target_include_directories(${spng_TARGET} PUBLIC
      $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/spng>
      $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
    )
    target_link_libraries(${spng_TARGET} PRIVATE ${SPNG_DEPENDENCIES})
    if(SPNG_USE_MINIZ)
        target_compile_definitions(${spng_TARGET} PUBLIC SPNG_USE_MINIZ)
    endif()
endforeach()

if(SPNG_INSTALL)
    set(project_config "${CMAKE_CURRENT_BINARY_DIR}/SPNGConfig.cmake")
    set(project_version_config "${CMAKE_CURRENT_BINARY_DIR}/SPNGConfigVersion.cmake")
    set(targets_export_name SPNGTargets)
    set(config_install_dir "${CMAKE_INSTALL_LIBDIR}/cmake/spng")

    configure_package_config_file(cmake/Config.cmake.in ${project_config}
        INSTALL_DESTINATION ${config_install_dir}
    )

    write_basic_package_version_file(${project_version_config}
        VERSION ${SPNG_VERSION}
        COMPATIBILITY SameMajorVersion
    )

    install(
        TARGETS ${spng_TARGETS}
        EXPORT ${targets_export_name}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
        INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    )

    install(FILES spng/spng.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})

    install(
        FILES ${project_config} ${project_version_config}
        DESTINATION ${config_install_dir}
    )

    install(
        EXPORT ${targets_export_name}
        NAMESPACE "spng::"
        DESTINATION ${config_install_dir}
    )

    if(NOT CMAKE_HOST_WIN32 OR CYGWIN OR MINGW)
        set(prefix      ${CMAKE_INSTALL_PREFIX})
        set(exec_prefix ${CMAKE_INSTALL_PREFIX})
        set(libdir      ${CMAKE_INSTALL_FULL_LIBDIR})
        set(includedir  ${CMAKE_INSTALL_FULL_INCLUDEDIR})
        set(LIBS        "-lspng")
        if(NOT WIN32)
            set(LIBS "${LIBS} -lm")
        endif()

        configure_file(${CMAKE_CURRENT_SOURCE_DIR}/cmake/libspng.pc.in ${CMAKE_CURRENT_BINARY_DIR}/spng.pc @ONLY)
        install(FILES ${CMAKE_CURRENT_BINARY_DIR}/spng.pc DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig)
    endif()
endif()
