require 'cocoapods/validator'
require 'cocoapods-project-gen/gen/swift_module_helper'
require 'fileutils'

module ProjectGen
  class ProjectGenerator < Pod::Validator
    include ProjectGen::SwiftModule

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
    def self.new_from_local(podspecs, source_urls, platforms = [], product_type = :framework, configuration = :release, swift_version = nil, use_modular_headers: false)
      generator = new(podspecs[0], source_urls, platforms)
      generator.local = false
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
      Pod::UI.print " -> #{a_spec ? a_spec.name : file.basename}\r" unless config.silent?
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

    # Perform analysis for a given spec (or subspec)
    #
    def install(spec, dir, &block)
      if spec.non_library_specification?
        error('spec', "Validating a non library spec (`#{spec.name}`) is not supported.")
        return false
      end
      platforms = send(:platforms_to_lint, spec)
      valid = platforms.send(fail_fast ? :all? : :each) do |platform|
        Pod::UI.message "\n\n#{spec} - Analyzing on #{platform} platform.".green.reversed
        @consumer = spec.consumer(platform)
        c_method = %i[setup_validation_environment create_app_project handle_local_pod
                      check_file_patterns install_pod validate_swift_version
                      add_app_project_import validate_vendored_dynamic_frameworks]
        begin
          c_method.each { |m| send(m) }
          valid = validated?
        end
        block.call(platform, pod_targets, valid) unless block&.nil?
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

    def handle_local_pod
      sandbox = Pod::Sandbox.new(@validation_dir + 'Pods')
      test_spec_names = consumer.spec.test_specs.select do |ts|
        ts.supported_on_platform?(consumer.platform_name)
      end.map(&:name)
      podfile = podfile_from_spec(consumer.platform_name, deployment_target, use_frameworks, test_spec_names,
                                  use_modular_headers, use_static_frameworks)

      @installer = Pod::Installer.new(sandbox, podfile)
      @installer.use_default_plugins = false
      @installer.has_dependencies = !spec.dependencies.empty?
      %i[prepare resolve_dependencies download_dependencies clean_pod_sources write_lockfiles].each do |m|
        case m
        when :clean_pod_sources
          copy_and_clean(sandbox)
          podspecs.each { |s| sandbox.development_pods.delete(s.name) }
          @installer.send(m)
        else
          @installer.send(m)
          next unless m == :resolve_dependencies

          podspecs.each { |s| sandbox.store_local_path(s.name, s.defined_in_file, absolute?(s.defined_in_file)) }
        end
      end
      library_targets = pod_targets.select { |target| target.build_as_library? }
      add_swift_library_compatibility_header(library_targets)
      @file_accessor = pod_targets.flat_map(&:file_accessors).find do |fa|
        fa.spec.name == consumer.spec.name
      end
    end

    def podspecs
      ps = [file]
      ps += external_podspecs.map { |pa| Pathname.new(pa) } if external_podspecs
      ps += include_podspecs.map { |pa| Pathname.new(pa) } if include_podspecs
      ps.uniq.map { |path| Pod::Specification.from_file(path) }
    end

    # @return [Bool]
    #
    def absolute?(path)
      Pathname(path).absolute? || path.to_s.start_with?('~')
    end

    def group_subspecs_by_platform(spec)
      specs_by_platform = {}
      [spec, *spec.recursive_subspecs].each do |ss|
        ss.available_platforms.each do |platform|
          specs_by_platform[platform] ||= []
          specs_by_platform[platform] << ss
        end
      end
      specs_by_platform
    end

    def copy(source, destination, specs_by_platform)
      path_list = Pod::Sandbox::PathList.new(source)
      file_accessors = specs_by_platform.flat_map do |platform, specs|
        specs.flat_map { |spec| Pod::Sandbox::FileAccessor.new(path_list, spec.consumer(platform)) }
      end
      used_files = Pod::Sandbox::FileAccessor.all_files(file_accessors)
      used_files.each do |path|
        path = Pathname(path)
        n_path = destination.join(path.relative_path_from(source))
        n_path.dirname.mkpath
        FileUtils.cp_r(path, n_path.dirname)
      end
    end

    def copy_and_clean(sandbox)
      podspecs.each do |spec|
        destination = config.sandbox_root + spec.name
        source = sandbox.pod_dir(spec.name)
        specs_by_platform = group_subspecs_by_platform(spec)
        destination.parent.mkpath
        FileUtils.rm_rf(destination)
        copy(source, destination, specs_by_platform)
      end
    end
  end
end
