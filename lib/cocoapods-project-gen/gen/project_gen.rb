require 'fileutils'

module ProjectGen
  autoload :PodDirCopyCleaner, 'cocoapods-project-gen/gen/pod/pod_copy_cleaner'
  class ProjectGenerator < Pod::Validator
    require 'cocoapods-project-gen/gen/pod/swift_module_helper'
    require 'cocoapods-project-gen/gen/pod/project_gen_helper'

    include Pod
    include ProjectGen::SwiftModule
    include ProjectGen::Helper

    # Initialize a new instance
    #
    # @param  [Array<Specification, Pathname, String>] podspecs
    #         the Specifications or the paths of the `podspec` files to used.
    #
    # @param  [Array<String>] source_urls
    #         the Source URLs to use in creating a {Podfile}.
    #
    # @param  [Array<String>] platforms
    #         the platforms to used.
    #
    # @param  [Symbol] either :framework or :static_library, depends on
    #         #build_as_framework?.
    #
    # @param  [Symbol] The name of the build configuration.
    #
    # @param  [String] the SWIFT_VERSION within the .swift-version file or nil.
    #
    # @param  [Boolean] Whether modular headers should be used for the installation.
    #
    def self.new_from_local(podspecs = [], source_urls = [Pod::TrunkSource::TRUNK_REPO_URL], platforms = [], product_type = :framework, configuration = :release, swift_version = nil, use_modular_headers: false)
      generator = new(podspecs[0], source_urls, platforms)
      generator.local = true
      generator.no_subspecs    = true
      generator.only_subspec   = nil
      generator.no_clean       = false
      generator.allow_warnings = true
      generator.use_frameworks = product_type == :dynamic_framework
      generator.use_static_frameworks = product_type == :framework
      generator.skip_import_validation = true
      generator.external_podspecs = podspecs.drop(1)
      generator.configuration = configuration
      generator.skip_tests = true
      generator.use_modular_headers = use_modular_headers
      generator.swift_version = swift_version unless swift_version.nil?
      generator
    end

    # Create app project
    #
    # @param [String, Pathname] dir the temporary directory used by the Gen.
    #
    # @param  [block<platform, pod_targets, valid>] &block the block to execute inside the lock.
    #
    def generate!(dir, &block)
      dir = Pathname(dir)
      @results = []
      # Replace default spec with a subspec if asked for
      a_spec = spec
      if spec && @only_subspec
        subspec_name = @only_subspec.start_with?(spec.root.name) ? @only_subspec : "#{spec.root.name}/#{@only_subspec}"
        a_spec = spec.subspec_by_name(subspec_name, true, true)
        @subspec_name = a_spec.name
      end
      @validation_dir = dir
      unless config.silent?
        podspecs.each do |spec|
          Pod::UI.print " -> #{spec.name}\r\n"
        end
      end
      $stdout.flush
      send(:perform_linting) if respond_to?(:perform_linting)
      install(a_spec, dir, &block) if a_spec && !quick
      Pod::UI.puts ' -> '.send(result_color) << (a_spec ? a_spec.to_s : file.basename.to_s)
      print_results
    end

    def pod_targets
      @installer.pod_targets
    end

    private

    def install(spec, dir, &block)
      if spec.non_library_specification?
        error('spec', "Validating a non library spec (`#{spec.name}`) is not supported.")
        return false
      end
      platforms = determine_platform
      begin
        setup_validation_environment
        create_app_project(platforms)
        handle_local_pod(platforms)
        install_pod(platforms)
        validate_swift_version
        add_app_project_import(platforms)
        validate_vendored_dynamic_frameworks(platforms)
        valid = validated?
        ts = pod_targets.each_with_object({}) do |pod_target, sum|
          name = pod_target.root_spec
          sum[name] ||= []
          sum[name] << pod_target
          sum
        end
        block.call(platforms, ts, valid, @no_clean) unless block&.nil?
        return false if fail_fast && !valid

        generate_subspec(spec, dir, &block) unless @no_subspecs
      rescue StandardError => e
        message = e.to_s
        raise Pod::Informative, "Encountered an unknown error\n\n#{message})\n\n#{e.backtrace * "\n"}"
      end
    end

    def generate_subspec(spec, dir, &block)
      spec.subspecs.reject(&:non_library_specification?).send(fail_fast ? :all? : :each) do |subspec|
        @subspec_name = subspec.name
        install(subspec, dir, &block)
      end
    end

    def handle_local_pod(platforms)
      sandbox = Pod::Sandbox.new(@validation_dir + 'Pods')
      podfile = podfile_from_spec(platforms, use_frameworks,
                                  use_modular_headers, use_static_frameworks)

      @installer = Pod::Installer.new(sandbox, podfile)
      @installer.use_default_plugins = false
      @installer.has_dependencies = podspecs.any? { |podspec| !podspec.all_dependencies.empty? }
      %i[prepare resolve_dependencies install_pod_sources run_podfile_pre_install_hooks clean_pod_sources
         write_lockfiles].each do |m|
        case m
        when :clean_pod_sources
          ProjectGen::PodDirCopyCleaner.new(include_specification).copy_and_clean(config.sandbox_root, sandbox)
          include_specification.each { |s| sandbox.development_pods.delete(s.name) }
          @installer.send(m)
        else
          @installer.send(m)
          next unless m == :resolve_dependencies

          # local --> source in local
          # no-local --> source from cdn
          # external_podspecs --> source in cdn
          # include_podspecs  --> source in local
          include_specification.each do |spec|
            sandbox.store_local_path(spec.name, spec.defined_in_file, Utils.absolute?(spec.defined_in_file))
          end
        end
      end
      library_targets = pod_targets.select(&:build_as_library?)
      add_swift_library_compatibility_header(library_targets)
    end
  end
end
