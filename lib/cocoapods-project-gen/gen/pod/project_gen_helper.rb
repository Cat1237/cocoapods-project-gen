module ProjectGen
  module Helper
    include Pod
    def self.app_name_with_platform(platform)
      "App-#{platform.symbolic_name}"
    end

    def podspecs
      additional_podspec_pods = external_podspecs ? Dir.glob(external_podspecs) : []
      additional_path_pods = (include_podspecs ? Dir.glob(include_podspecs) : []).reject do |path|
        spec.name == Pod::Specification.from_file(path).name
      end - additional_podspec_pods
      (additional_podspec_pods + additional_path_pods).inject([spec]) do |sum, path|
        sum << Pod::Specification.from_file(path)
      end.uniq
    end

    def include_specification
      (include_podspecs ? Dir.glob(include_podspecs) : []).map do |path|
        Pod::Specification.from_file(path)
      end
    end

    # Returns a list of platforms to lint for a given Specification
    #
    # @return [Array<Platform>] platforms to lint for the given specification
    #
    def determine_platform
      platforms = podspecs.flat_map(&:available_platforms).uniq
      platforms = platforms.map do |platform|
        default = Pod::Podfile::TargetDefinition::PLATFORM_DEFAULTS[platform.name]
        deployment_target = podspecs.map do |library_spec|
          d_t = library_spec.subspec_by_name(subspec_name).deployment_target(platform.name)
          Pod::Version.new(d_t || default)
        end.max
        if platform.name == :ios && use_frameworks
          minimum = Pod::Version.new('8.0')
          deployment_target = [deployment_target, minimum].max
        end
        Pod::Platform.new(platform.name, deployment_target)
      end.uniq
      return platforms if @platforms.empty?

      # Validate that the platforms specified are actually supported by the spec
      @platforms.map do |platform|
        matching_platform = platforms.find { |p| p.name == platform.name }
        unless matching_platform
          raise Informative, "Platform `#{platform}` is not supported by specification `#{spec}`."
        end

        matching_platform
      end.uniq
    end

    def validate_vendored_dynamic_frameworks(platforms)
      platform = platforms.find { |pl| pl.name == :ios }
      targets = pod_targets.select { |t| t.platform.name == :ios }
      targets.flat_map(&:file_accessors).each do |file_accessor|
        deployment_target = platform.deployment_target
        dynamic_frameworks = file_accessor.vendored_dynamic_frameworks
        dynamic_libraries = file_accessor.vendored_dynamic_libraries
        if (dynamic_frameworks.count.positive? || dynamic_libraries.count.positive?) && platform.name == :ios &&
           (deployment_target.nil? || deployment_target.major < 8)
          error('dynamic', 'Dynamic frameworks and libraries are only supported on iOS 8.0 and onwards.')
        end
      end
    end

    def create_app_project(platforms)
      p_path = validation_dir + 'App.xcodeproj'
      app_project = if p_path.exist?
                      Xcodeproj::Project.open(p_path)
                    else
                      Xcodeproj::Project.new(File.join(validation_dir, 'App.xcodeproj'))
                    end
      platforms.each do |platform|
        app_target = Pod::Generator::AppTargetHelper.add_app_target(app_project, platform.name,
                                                                    platform.deployment_target.to_s, Helper.app_name_with_platform(platform))
        sandbox = Pod::Sandbox.new(config.sandbox_root)
        info_plist_path = app_project.path.dirname.+("App/#{Helper.app_name_with_platform(platform)}-Info.plist")
        Pod::Installer::Xcode::PodsProjectGenerator::TargetInstallerHelper.create_info_plist_file_with_sandbox(sandbox,
                                                                                                               info_plist_path,
                                                                                                               app_target,
                                                                                                               '1.0.0',
                                                                                                               Pod::Platform.new(platform.name),
                                                                                                               :appl,
                                                                                                               build_setting_value: "$(SRCROOT)/App/#{Helper.app_name_with_platform(platform)}-Info.plist")
        Pod::Generator::AppTargetHelper.add_swift_version(app_target, derived_swift_version)
        app_target.build_configurations.each do |config|
          # Lint will fail if a AppIcon is set but no image is found with such name
          # Happens only with Static Frameworks enabled but shouldn't be set anyway
          config.build_settings.delete('ASSETCATALOG_COMPILER_APPICON_NAME')
          # Ensure this is set generally but we have seen an issue with ODRs:
          # see: https://github.com/CocoaPods/CocoaPods/issues/10933
          config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.cocoapods.${PRODUCT_NAME:rfc1034identifier}'
        end
      end
      app_project.save
      app_project.recreate_user_schemes
    end

    # It creates a podfile in memory and builds a library containing the pod
    # for all available platforms with xcodebuild.
    #
    def install_pod(platforms)
      %i[validate_targets generate_pods_project integrate_user_project
         perform_post_install_actions].each { |m| @installer.send(m) }
      configure_pod_targets(@installer.target_installation_results)

      platforms.each do |platform|
        validate_dynamic_framework_support(platform.name, @installer.aggregate_targets, platform.deployment_target.to_s)
      end
      @installer.pods_project.save
    end

    # Produces an error of dynamic frameworks were requested but are not supported by the deployment target
    #
    # @param [Array<AggregateTarget>] aggregate_targets
    #        The aggregate targets installed by the installer
    #
    # @param [String,Version] deployment_target
    #        The deployment target of the installation
    #
    def validate_dynamic_framework_support(platform_name, aggregate_targets, deployment_target)
      return unless platform_name == :ios
      return unless deployment_target.nil? || Pod::Version.new(deployment_target).major < 8

      aggregate_targets.each do |target|
        next unless target.pod_targets.any?(&:uses_swift?)

        uses_xctest = target.spec_consumers.any? do |c|
          (c.frameworks + c.weak_frameworks).include? 'XCTest'
        end
        unless uses_xctest
          error('swift',
                'Swift support uses dynamic frameworks and is therefore only supported on iOS > 8.')
        end
      end
    end

    def add_app_project_import(platforms)
      app_project = Xcodeproj::Project.open(validation_dir + 'App.xcodeproj')
      app_target = app_project.targets.first
      pod_target = validation_pod_target
      platforms.each do |platform|
        Pod::Generator::AppTargetHelper.add_app_project_import(app_project, app_target, pod_target,
                                                               platform.name, Helper.app_name_with_platform(platform))
      end

      Pod::Generator::AppTargetHelper.add_xctest_search_paths(app_target) if @installer.pod_targets.any? do |pt|
                                                                               pt.spec_consumers.any? do |c|
                                                                                 c.frameworks.include?('XCTest') || c.weak_frameworks.include?('XCTest')
                                                                               end
                                                                             end
      if @installer.pod_targets.any?(&:uses_swift?)
        Pod::Generator::AppTargetHelper.add_empty_swift_file(app_project, app_target)
      end
      app_project.save
      platforms.each do |platform|
        Xcodeproj::XCScheme.share_scheme(app_project.path, Helper.app_name_with_platform(platform))
      end
      # Share the pods xcscheme only if it exists. For pre-built vendored pods there is no xcscheme generated.
      return unless shares_pod_target_xcscheme?(pod_target)

      Xcodeproj::XCScheme.share_scheme(@installer.pods_project.path, pod_target.label)
    end

    # @param  [String] platform_name
    #         the name of the platform, which should be declared
    #         in the Podfile.
    #
    # @param  [String] deployment_target
    #         the deployment target, which should be declared in
    #         the Podfile.
    #
    # @param  [Boolean] use_frameworks
    #         whether frameworks should be used for the installation
    #
    # @param [Array<String>] test_spec_names
    #         the test spec names to include in the podfile.
    #
    # @return [Podfile] a podfile that requires the specification on the
    #         current platform.
    #
    # @note   The generated podfile takes into account whether the linter is
    #         in local mode.
    #
    def podfile_from_spec(platforms, use_frameworks = true, use_modular_headers = false, use_static_frameworks = false)
      name = subspec_name || spec.name
      podspec  = file.realpath
      # local    = local?
      urls     = source_urls
      additional_podspec_pods = (external_podspecs ? Dir.glob(external_podspecs) : []).select do |path|
        spec.name != Pod::Specification.from_file(path).name
      end
      additional_path_pods = (include_podspecs ? Dir.glob(include_podspecs) : []).select do |path|
        spec.name != Pod::Specification.from_file(path).name
      end - additional_podspec_pods
      Pod::Podfile.new do
        install! 'cocoapods', deterministic_uuids: false, warn_for_unused_master_specs_repo: false
        # By default inhibit warnings for all pods, except the one being validated.
        inhibit_all_warnings!
        urls.each { |u| source(u) }
        platforms.each do |platform|
          app_name = ProjectGen::Helper.app_name_with_platform(platform)
          target(app_name) do
            if use_static_frameworks
              use_frameworks!(linkage: :static)
            else
              use_frameworks!(use_frameworks)
            end
            use_modular_headers! if use_modular_headers
            platform(platform.name, platform.deployment_target.to_s)

            spec = Pod::Specification.from_file(podspec)
            pod name, podspec: podspec.to_s, inhibit_warnings: false if spec.supported_on_platform?(platform)

            additional_path_pods.each do |podspec_path|
              podspec_name = File.basename(podspec_path, '.*')
              p_spec = Pod::Specification.from_file(podspec_path)
              pod podspec_name, podspec: podspec_path if p_spec.supported_on_platform?(platform)
              # pod podspec_name, path: File.dirname(podspec_path) if p_spec.supported_on_platform?(platform)
            end

            additional_podspec_pods.each do |podspec_path|
              p_spec = Pod::Specification.from_file(podspec_path)
              podspec_name = File.basename(podspec_path, '.*')
              pod podspec_name, podspec: podspec_path if p_spec.supported_on_platform?(platform)
            end

            next unless spec.supported_on_platform?(platform)
          end
        end
      end
    end
  end
end
