require 'fileutils'

module ProjectGen
  autoload :PodDirCopyCleaner, 'cocoapods-project-gen/gen/pod/pod_copy_cleaner'

  class ProjectGenerator
    require 'cocoapods-project-gen/gen/pod/swift_module_helper'
    require 'cocoapods-project-gen/gen/pod/project_gen_helper'

    include ProjectGen::SwiftModule
    include ProjectGen::Helper
    include Pod::Config::Mixin

    # !@group results

    attr_reader :results
    #-------------------------------------------------------------------------#

    #  @!group Configuration

    # When multiple dependencies with different sources, use latest.
    #
    attr_accessor :use_latest

    # @return [String] The SWIFT_VERSION that should be used to validate the pod. This is set by passing the
    # `--swift-version` parameter during validation.
    #
    attr_accessor :swift_version
    # @return [Boolean] whether the linter should not clean up temporary files
    #         for inspection.
    #
    attr_accessor :no_clean

    # @return [Boolean] whether the linter should fail as soon as the first build
    #         variant causes an error. Helpful for i.e. multi-platforms specs,
    #         specs with subspecs.
    #
    attr_accessor :fail_fast

    # @return [Boolean] whether the validation should be performed against the root of
    #         the podspec instead to its original source.
    #
    #
    attr_accessor :local
    alias local? local

    # @return [Boolean] Whether the validator should fail on warnings, or only on errors.
    #
    attr_accessor :allow_warnings

    # @return [String] name of the subspec to check, if nil all subspecs are checked.
    #
    attr_accessor :only_subspecs

    # @return [Boolean] Whether frameworks should be used for the installation.
    #
    attr_accessor :use_frameworks

    # @return [Boolean] Whether modular headers should be used for the installation.
    #
    attr_accessor :use_modular_headers

    # @return [Boolean] Whether static frameworks should be used for the installation.
    #
    attr_accessor :use_static_frameworks

    # @return [String] A glob for podspecs to be used during building of
    #         the local Podfile via :path.
    #
    attr_accessor :include_podspecs

    # @return [String] A glob for podspecs to be used during building of
    #         the local Podfile via :podspec.
    #
    attr_accessor :external_podspecs

    # !@group Helpers

    # @return [Array<String>] an array of source URLs used to create the
    #         {Podfile} used in the linting process
    #
    attr_reader :source_urls

    # @return configuration
    #
    attr_accessor :configuration

    #-------------------------------------------------------------------------#
    # @return [Boolean]
    #

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
      generator = new(source_urls, platforms)
      generator.local = true
      generator.no_subspecs = true
      generator.only_subspecs = nil
      generator.no_clean       = false
      generator.allow_warnings = true
      generator.use_frameworks = product_type == :dynamic_framework
      generator.use_static_frameworks = product_type == :framework
      generator.include_podspecs = podspecs
      generator.configuration = configuration
      generator.use_modular_headers = use_modular_headers
      generator.swift_version = swift_version
      generator
    end

    # Initialize a new instance
    #
    # @param  [Array<String>] source_urls
    #         the Source URLs to use in creating a {Podfile}.
    #
    # @param  [Array<String>] platforms
    #         the platforms to lint.
    #
    def initialize(source_urls, platforms = [])
      @source_urls = source_urls.map { |url| config.sources_manager.source_with_name_or_url(url) }.map(&:url)
      @platforms = platforms.map do |platform|
        result =  case platform.to_s.downcase
                  # Platform doesn't recognize 'macos' as being the same as 'osx' when initializing
                  when 'macos' then Pod::Platform.macos
                  else Pod::Platform.new(platform, nil)
                  end
        unless Constants.valid_platform?(result)
          raise Informative, "Unrecognized platform `#{platform}`. Valid platforms: #{VALID_PLATFORMS.join(', ')}"
        end

        result
      end
      @allow_warnings = true
      @use_frameworks = true
      @use_latest = true
    end

    # Create app project
    #
    # @param [String, Pathname] dir the temporary directory used by the Gen.
    #
    # @param  [block<platforms, pod_targets, valid>] &block the block to execute inside the lock.
    #
    def generate!(work_dir, &block)
      @project_gen_dir = Pathname(work_dir)
      @results = Results.new
      unless config.silent?
        podspecs.each do |spec|
          subspecs = determine_subspecs[spec]
          if subspecs && !subspecs.empty?
            subspecs.each { |s| Results.puts " -> #{s}\r\n" }
          else
            Results.puts " -> #{spec.name}\r\n"
          end
        end
      end
      $stdout.flush
      perform_linting
      platforms, pod_targets, valid = install
      @results.print_results
      block.call(platforms, pod_targets, @clean, @fail_fast) if !block.nil? && valid
    end

    # @return [Pathname] the temporary directory used by the linter.
    #
    def project_gen_dir
      @project_gen_dir ||= Pathname(Dir.mktmpdir(['cocoapods-project-gen-', "-#{spec.name}"]))
    end

    private

    def install
      podspec = podspecs.find(&:non_library_specification?)
      if podspec
        error('spec', "Validating a non library spec (`#{podspec.name}`) is not supported.")
        [determine_platforms, specs_for_pods, false]
      else
        begin
          setup_gen_environment
          create_app_project
          download_or_copy_pod
          install_pod
          validate_swift_version
          add_app_project_import
          validate_vendored_dynamic_frameworks
          valid = validated?
          results.note('Project gen', 'finish!') if valid
          [determine_platforms, specs_for_pods, valid]
        rescue StandardError => e
          message = e.to_s
          message << "\n" << e.backtrace.join("\n") << "\n" if config.verbose?
          error('unknown', "Encountered an unknown error (#{message}) during validation.")
          [determine_platforms, specs_for_pods, false]
        end
      end
    end

    def download_or_copy_pod
      sandbox = Pod::Sandbox.new(@project_gen_dir + 'Pods')
      podfile = podfile_from_spec(use_frameworks, use_modular_headers, use_static_frameworks)
      @installer = Pod::Installer.new(sandbox, podfile)
      @installer.use_default_plugins = false
      @installer.has_dependencies = podspecs.any? { |podspec| !podspec.all_dependencies.empty? }
      %i[prepare resolve_dependencies install_pod_sources run_podfile_pre_install_hooks clean_pod_sources
         write_lockfiles].each do |m|
        case m
        when :clean_pod_sources
          ProjectGen::PodDirCopyCleaner.new(include_specifications).copy_and_clean(config.sandbox_root, sandbox)
          include_specifications.each { |s| sandbox.development_pods.delete(s.name) }
          @installer.send(m)
        else
          @installer.send(m)
          next unless m == :resolve_dependencies

          # local --> source in local
          # no-local --> source from cdn
          # external_podspecs --> source in cdn
          # include_podspecs  --> source in local
          include_specifications.each do |spec|
            sandbox.store_local_path(spec.name, spec.defined_in_file, Utils.absolute?(spec.defined_in_file))
          end
        end
      end
      add_swift_library_compatibility_header(@installer.pod_targets)
    end
  end
end
