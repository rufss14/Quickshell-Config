# Trimmed from caelestia-dots/shell's plugin/cmake/qml-module.cmake (GPLv3):
# their version links every module against a shared precompiled-header target
# and a DISTRIBUTOR cache var this project has no equivalent for. What's left
# is the actual mechanics — qt_add_qml_module plus installing the backing
# target, the plugin target, qmldir and the typeinfo to the right relative
# paths so the module is importable from an arbitrary QML_IMPORT_PATH entry.
function(qml_module arg_TARGET)
    cmake_parse_arguments(PARSE_ARGV 1 arg "" "URI" "SOURCES;QML_FILES;QML_SINGLETONS;DEPENDENCIES;LIBRARIES")

    set_source_files_properties(${arg_QML_SINGLETONS} PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

    string(REPLACE "." "/" arg_URI_PATH "${arg_URI}")

    qt_add_qml_module(${arg_TARGET}
        URI ${arg_URI}
        VERSION 1.0
        SOURCES ${arg_SOURCES}
        QML_FILES ${arg_QML_FILES} ${arg_QML_SINGLETONS}
        DEPENDENCIES ${arg_DEPENDENCIES}
        # Qt expects the build-tree output dir to end in the module's own
        # target path (Qmllint/qmlls read it to find sibling modules) — the
        # CMake default (this target's own binary dir) doesn't, which is a
        # harmless warning but easy to silence properly.
        OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml/${arg_URI_PATH}"
    )

    qt_query_qml_module(${arg_TARGET}
        URI module_uri
        PLUGIN_TARGET module_plugin_target
        TARGET_PATH module_target_path
        QMLDIR module_qmldir
        TYPEINFO module_typeinfo
    )

    message(STATUS "Created QML module: ${module_uri} -> ${INSTALL_QMLDIR}/${module_target_path}")

    # Same split Caelestia's helper uses: the backing (C++) target and the
    # plugin target can't both live in the module's own directory, or a second
    # module importing this one can't find its backing lib.
    string(REPLACE "/" ";" uri_parts "${module_target_path}")
    list(GET uri_parts 0 top_level)
    set(backing_lib_dir "${INSTALL_QMLDIR}/${top_level}/lib")
    set(module_dir "${INSTALL_QMLDIR}/${module_target_path}")

    install(TARGETS ${arg_TARGET}
        LIBRARY DESTINATION "${backing_lib_dir}"
        RUNTIME DESTINATION "${backing_lib_dir}"
    )
    install(TARGETS "${module_plugin_target}"
        LIBRARY DESTINATION "${module_dir}"
        RUNTIME DESTINATION "${module_dir}"
    )
    install(FILES "${module_qmldir}" DESTINATION "${module_dir}")
    install(FILES "${module_typeinfo}" DESTINATION "${module_dir}")

    target_link_libraries(${arg_TARGET} PRIVATE Qt::Core Qt::Qml ${arg_LIBRARIES})

    file(RELATIVE_PATH plugin_to_lib "/${module_target_path}" "/${top_level}/lib")
    set_property(TARGET ${module_plugin_target} APPEND PROPERTY INSTALL_RPATH "$ORIGIN/${plugin_to_lib}")
endfunction()
