module ProjectGen
  module Helper
    include Pod

    def self.app_target_name(platform)
      "App-#{platform.string_name}"
    end

    private

    # The specifications matching the specified pod name
    #
    # @param  [String] pod_name the name of the pod
    #
    # @return [Hash{Specification => Array<Taget>}] the specifications grouped by platform
    #
    def specs_for_pods
      @installer.pod_targets.each_with_object({}) do |pod_target, hash|
        hash[pod_target.root_spec] ||= []
        hash[pod_target.root_spec] << pod_target
      end
    end

    def setup_gen_environment
      project_gen_dir.rmtree if project_gen_dir.exist?
      project_gen_dir.mkpath
      @original_config = Pod::Config.instance.clone
      config.installation_root   = project_gen_dir
      config.silent              = !config.verbose
    end

    # !@group Lint steps
    def perform_linting
      podspecs.each do |podspec|
        linter = Pod::Specification::Linter.new(podspec)
        linter.lint
        @results.results.concat(linter.results.to_a)
      end
    end

    def podspecs
      return @podspecs if defined? @podspecs

      additional_podspec_pods = external_podspecs ? Dir.glob(external_podspecs) : []
      additional_path_pods = include_podspecs ? Dir.glob(include_podspecs) : []
      @podspecs = (additional_podspec_pods + additional_path_pods).uniq.each_with_object({}) do |path, hash|
        spec = Pod::Specification.from_file(path)
        old_spec = hash[spec.name]
        if old_spec && use_latest
          hash[spec.name] = [old_spec, spec].max { |old, new| old.version <=> new.version }
        else
          hash[spec.name] = spec
        end
      end.values
    end

    def include_specifications
      (include_podspecs ? Dir.glob(include_podspecs) : []).map do |path|
        Pod::Specification.from_file(path)
      end
    end

    # Returns a list of platforms to lint for a given Specification
    #
    # @return [Array<Platform>] platforms to lint for the given specification
    #
    def determine_platforms
      return @determine_platforms if defined?(@determine_platforms) && @determine_platforms == @platform

      platforms = podspecs.flat_map(&:available_platforms).uniq
      platforms = platforms.map do |platform|
        default = Pod::Podfile::TargetDefinition::PLATFORM_DEFAULTS[platform.name]
        deployment_target = podspecs.flat_map do |library_spec|
          subspecs = determine_subspecs[library_spec]
          if subspecs && !subspecs.empty?
            subspecs.map { |s| Pod::Version.new(s.deployment_target(platform.name) || default) }
          else
            Pod::Version.new(library_spec.deployment_target(platform.name) || default)
          end
        end.max
        if platform.name == :ios && use_frameworks
          minimum = Pod::Version.new('8.0')
          deployment_target = [deployment_target, minimum].max
        end
        Pod::Platform.new(platform.name, deployment_target)
      end.uniq

      unless @platforms.empty?
        # Validate that the platforms specified are actually supported by the spec
        platforms = @platforms.map do |platform|
          matching_platform = platforms.find { |p| p.name == platform.name }
          unless matching_platform
            raise Informative, "Platform `#{platform}` is not supported by specification `#{spec}`."
          end

          matching_platform
        end.uniq
      end
      @platform = platforms
      @determine_platforms = platforms
    end

    def determine_subspecs
      return @determine_subspecs if defined? @determine_subspecs
      return {} if @only_subspecs.nil?

      subspecs = @only_subspecs.dup
      ha = podspecs.each_with_object({}) do |podspec, hash|
        return hash if subspecs.empty?

        base_name = podspec.name
        s_s = []
        subspecs.delete_if { |ss| s_s << podspec.subspec_by_name(ss, false) if ss.split('/').shift == base_name }
        s_s.compact!
        hash[podspec] = s_s unless s_s.empty?
      end
      subspecs.each { |s| results.warning('subspecs', "#{s} should use NAME/NAME.") }
      @determine_subspecs = ha
    end

    def validate_vendored_dynamic_frameworks
      platform = determine_platforms.find { |pl| pl.name == :ios }
      targets = relative_pod_targets_from_platfrom(platform)
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

    def create_app_project
      p_path = project_gen_dir + 'App.xcodeproj'
      app_project = if p_path.exist?
                      Xcodeproj::Project.open(p_path)
                    else
                      Xcodeproj::Project.new(File.join(project_gen_dir, 'App.xcodeproj'))
                    end
      determine_platforms.each do |platform|
        app_target = Pod::Generator::AppTargetHelper.add_app_target(app_project, platform.name,
                                                                    platform.deployment_target.to_s, Helper.app_target_name(platform))
        sandbox = Pod::Sandbox.new(config.sandbox_root)
        info_plist_path = app_project.path.dirname.+("App/#{Helper.app_target_name(platform)}-Info.plist")
        Pod::Installer::Xcode::PodsProjectGenerator::TargetInstallerHelper.create_info_plist_file_with_sandbox(sandbox,
                                                                                                               info_plist_path,
                                                                                                               app_target,
                                                                                                               '1.0.0',
                                                                                                               Pod::Platform.new(platform.name),
                                                                                                               :appl,
                                                                                                               build_setting_value: "$(SRCROOT)/App/#{Helper.app_target_name(platform)}-Info.plist")
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
    def install_pod
      %i[validate_targets generate_pods_project integrate_user_project
         perform_post_install_actions].each { |m| @installer.send(m) }
      configure_pod_targets(@installer.target_installation_results)

      determine_platforms.each do |platform|
        validate_dynamic_framework_support(platform.name, @installer.aggregate_targets, platform.deployment_target.to_s)
      end
      @installer.pods_project.save
    end

    # @param [Array<Hash{String, TargetInstallationResult}>] target_installation_results
    #        The installation results to configure
    #
    def configure_pod_targets(target_installation_results)
      target_installation_results.first.values.each do |pod_target_installation_result|
        pod_target = pod_target_installation_result.target
        native_target = pod_target_installation_result.native_target
        native_target.build_configuration_list.build_configurations.each do |build_configuration|
          (build_configuration.build_settings['OTHER_CFLAGS'] ||= '$(inherited)') << ' -Wincomplete-umbrella'
          next unless pod_target.uses_swift?

          # The Swift version for the target being validated can be overridden by `--swift-version` or the
          # `.swift-version` file so we always use the derived Swift version.
          #
          # For dependencies, if the derived Swift version is supported then it is the one used. Otherwise, the Swift
          # version for dependencies is inferred by the target that is integrating them.
          swift_version = pod_target.spec_swift_versions.map(&:to_s).find do |v|
            v == derived_swift_version
          end || pod_target.swift_version
          build_configuration.build_settings['SWIFT_VERSION'] = swift_version
        end
        pod_target_installation_result.test_specs_by_native_target.each do |test_native_target, test_spec|
          next unless pod_target.uses_swift_for_spec?(test_spec)

          test_native_target.build_configuration_list.build_configurations.each do |build_configuration|
            swift_version = pod_target == validation_pod_target ? derived_swift_version : pod_target.swift_version
            build_configuration.build_settings['SWIFT_VERSION'] = swift_version
          end
        end
      end
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

    # @return [Boolean]
    #
    def validated?
      results.result_type != :error && (results.result_type != :warning || allow_warnings)
    end

    # Returns the pod target for the pod being relatived. Installation must have occurred before this can be invoked.
    #
    def relative_pod_targets_from_platfrom(platform)
      @installer.pod_targets.select { |pt| pt.platform.name == platform.name }
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
    def podfile_from_spec(use_frameworks = true, use_modular_headers = false, use_static_frameworks = false)
      urls = source_urls
      all_podspec_pods = podspecs
      platforms = determine_platforms
      d_subspecs = determine_subspecs
      Pod::Podfile.new do
        install! 'cocoapods', deterministic_uuids: false, warn_for_unused_master_specs_repo: false
        # By default inhibit warnings for all pods, except the one being validated.
        inhibit_all_warnings!
        urls.each { |u| source(u) }
        platforms.each do |platform|
          app_name = ProjectGen::Helper.app_target_name(platform)
          target(app_name) do
            if use_static_frameworks
              use_frameworks!(linkage: :static)
            else
              use_frameworks!(use_frameworks)
            end
            use_modular_headers! if use_modular_headers
            platform(platform.name, platform.deployment_target.to_s)

            all_podspec_pods.each do |podspec|
              subspecs = d_subspecs[podspec]
              if subspecs && !subspecs.empty?
                subspecs.each do |s|
                  if s.supported_on_platform?(platform)
                    pod s.name, podspec: s.defined_in_file.to_s,
                                inhibit_warnings: false
                  end
                end
              elsif podspec.supported_on_platform?(platform)
                pod podspec.name, podspec: podspec.defined_in_file.to_s,
                                  inhibit_warnings: false
              end
            end
          end
        end
      end
    end

    def add_app_project_import
      app_project = Xcodeproj::Project.open(project_gen_dir + 'App.xcodeproj')
      app_project.targets.each do |app_target|
        platform = determine_platforms.find { |pl| pl.name == app_target.platform_name }
        pod_targets = relative_pod_targets_from_platfrom(platform)
        pod_targets.each do |pod_target|
          Pod::Generator::AppTargetHelper.add_app_project_import(app_project, app_target, pod_target, platform.name,
                                                                 Helper.app_target_name(platform))
        end
        Pod::Generator::AppTargetHelper.add_xctest_search_paths(app_target) if pod_targets.any? do |pt|
          pt.spec_consumers.any? do |c|
            c.frameworks.include?('XCTest') || c.weak_frameworks.include?('XCTest')
          end
        end
        Pod::Generator::AppTargetHelper.add_empty_swift_file(app_project, app_target) if pod_targets.any?(&:uses_swift?)
        app_project.save
        Xcodeproj::XCScheme.share_scheme(app_project.path, Helper.app_target_name(platform))
        pod_targets.each do |pod_target|
          if shares_pod_target_xcscheme?(pod_target)
            Xcodeproj::XCScheme.share_scheme(@installer.pods_project.path,
                                             pod_target.label)
          end
        end
      end
    end

    def shares_pod_target_xcscheme?(pod_target)
      Pathname.new(@installer.pods_project.path + pod_target.label).exist?
    end
  end
end
