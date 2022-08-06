module ProjectGen
  module SwiftModule
    # @return [String] the SWIFT_VERSION within the .swift-version file or nil.
    #
    def dot_swift_version(podspec)
      file = podspec.defined_in_file
      swift_version_path = file.dirname + '.swift-version'
      return unless swift_version_path.exist?

      swift_version_path.read.strip
    end

    # @return [String] The derived Swift version to use for validation. The order of precedence is as follows:
    #         - The `--swift-version` parameter is always checked first and honored if passed.
    #         - The `swift_versions` DSL attribute within the podspec, in which case the latest version is always chosen.
    #         - The Swift version within the `.swift-version` file if present.
    #         - If none of the above are set then the `#DEFAULT_SWIFT_VERSION` is used.
    #
    def derived_swift_version
      @derived_swift_version ||= if swift_version
                                   swift_version
                                 else
                                   version = podspecs.map do |podspec|
                                     podspec.swift_versions.max || dot_swift_version(podspec)
                                   end.compact.max
                                   if version
                                     version.to_s
                                   else
                                     Constants::DEFAULT_SWIFT_VERSION
                                   end
                                 end
    end

    # Performs validation for the version of Swift used during validation.
    #
    # An error will be displayed if the user has provided a `swift_versions` attribute within the podspec but is also
    # using either `--swift-version` parameter or a `.swift-version` file with a Swift version that is not declared
    # within the attribute.
    #
    # The user will be warned that the default version of Swift was used if the following things are true:
    #   - The project uses Swift at all
    #   - The user did not supply a Swift version via a parameter
    #   - There is no `swift_versions` attribute set within the specification
    #   - There is no `.swift-version` file present either.
    #
    def validate_swift_version

      specs_for_pods.each_pair do |spec, pod_targets|
        next unless pod_targets.any?(&:uses_swift?)

        spec_swift_versions = spec.swift_versions.map(&:to_s)

        dot_swift = dot_swift_version(spec)
        unless spec_swift_versions.empty?
          message = nil
          if !dot_swift.nil? && !spec_swift_versions.include?(dot_swift)
            message = "Specification `#{spec.name}` specifies inconsistent `swift_versions` (#{spec_swift_versions.map do |s|
                                                                                                 "`#{s}`"
                                                                                               end.to_sentence}) compared to the one present in your `.swift-version` file (`#{dot_swift_version}`). " \
                      'Please remove the `.swift-version` file which is now deprecated and only use the `swift_versions` attribute within your podspec.'
          elsif !swift_version.nil? && !spec_swift_versions.include?(swift_version)
            message = "Specification `#{spec.name}` specifies inconsistent `swift_versions` (#{spec_swift_versions.map do |s|
                                                                                                 "`#{s}`"
                                                                                               end.to_sentence}) compared to the one passed during gen (`#{swift_version}`)."
          end
          unless message.nil?
            @results.error('swift', message)
            break
          end
        end

        if swift_version.nil? && spec.swift_versions.empty?
          if !dot_swift.nil?
            # The user will be warned to delete the `.swift-version` file in favor of the `swift_versions` DSL attribute.
            # This is intentionally not a lint warning since we do not want to break existing setups and instead just soft
            # deprecate this slowly.
            #
            Pod::UI.warn 'Usage of the `.swift_version` file has been deprecated! Please delete the file and use the ' \
              "`swift_versions` attribute within your podspec instead.\n".yellow
          else
            results.warning('swift',
                    'The generator used ' \
                    "Swift `#{Constants::DEFAULT_SWIFT_VERSION}` by default because no Swift version was specified. " \
                    'To specify a Swift version during validation, add the `swift_versions` attribute in your podspec. ' \
                    'Note that usage of a `.swift-version` file is now deprecated.')
          end
        end
      end
    end
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
      targets.select(&:build_as_library?).each do |target|
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
          name: 'Copy Copy generated module and compatibility header',
          script: shell_script
        }]
      end
    end
  end
end
