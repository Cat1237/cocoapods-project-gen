require 'cocoapods'

module ProjectGen
  module SwiftModule

    # Adds a shell script phase, intended only for library targets that contain swift,
    # to copy the ObjC compatibility header (the -Swift.h file that the swift compiler generates)
    # to the built products directory. Additionally, the script phase copies the module map, appending a `.Swift`
    # submodule that references the (moved) compatibility header. Since the module map has been moved, the umbrella header
    # is _also_ copied, so that it is sitting next to the module map. This is necessary for a successful archive build.
    #
    # @param  [PBXNativeTarget] native_target
    #         the native target to add the Swift static library script phase into.
    #
    # @return [Void]
    #
    def add_swift_library_compatibility_header(targets)
      targets.each do |target|
        relative_module_map_path = target.module_map_path.relative_path_from(target.sandbox.root)
        relative_umbrella_header_path = target.umbrella_header_path.relative_path_from(target.sandbox.root)
        shell_script = <<-SH.strip_heredoc
              COMPATIBILITY_HEADER_ROOT_PATH="${SRCROOT}/${PRODUCT_MODULE_NAME}/#{Constants::COPY_LIBRARY_SWIFT_HEADERS}"
              COPY_MODULE_MAP_PATH="${COMPATIBILITY_HEADER_ROOT_PATH}/${PRODUCT_MODULE_NAME}.modulemap"
              ditto "${PODS_ROOT}/#{relative_module_map_path}" "${COPY_MODULE_MAP_PATH}"
              UMBRELLA_HEADER_PATH="${PODS_ROOT}/#{relative_umbrella_header_path}"
              if test -f "$UMBRELLA_HEADER_PATH"; then
                ditto "$UMBRELLA_HEADER_PATH" "${COMPATIBILITY_HEADER_ROOT_PATH}"
              fi
        SH

        target.root_spec.script_phases ||= []
        target.root_spec.script_phases += [{ name: 'Copy Copy generated module header', script: shell_script }]
        next unless target.uses_swift?

        shell_script = <<-SH.strip_heredoc
              COMPATIBILITY_HEADER_ROOT_PATH="${SRCROOT}/${PRODUCT_MODULE_NAME}/#{Constants::COPY_LIBRARY_SWIFT_HEADERS}"
              COPY_COMPATIBILITY_HEADER_PATH="${COMPATIBILITY_HEADER_ROOT_PATH}/${PRODUCT_MODULE_NAME}-Swift.h"#{' '}
              COPY_MODULE_MAP_PATH="${COMPATIBILITY_HEADER_ROOT_PATH}/${PRODUCT_MODULE_NAME}.modulemap"
              ditto "${DERIVED_SOURCES_DIR}/${PRODUCT_MODULE_NAME}-Swift.h" "${COPY_COMPATIBILITY_HEADER_PATH}"#{' '}
              ditto "${BUILT_PRODUCTS_DIR}/${PRODUCT_MODULE_NAME}.swiftmodule" "${COMPATIBILITY_HEADER_ROOT_PATH}/${PRODUCT_MODULE_NAME}.swiftmodule"#{' '}
              printf "\\n\\nmodule ${PRODUCT_MODULE_NAME}.Swift {\\n  header \\"${PRODUCT_MODULE_NAME}-Swift.h\\"\\n  requires objc\\n}\\n" >> "${COPY_MODULE_MAP_PATH}"
        SH
        target.root_spec.script_phases += [{
          name: 'Copy Copy generated compatibility header',
          script: shell_script
        }]
      end
    end
  end
end
