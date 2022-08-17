# frozen_string_literal: true

module ProjectGen
  class Command
    # hmap file gen cmd
    class Gen < Command
      # summary
      self.summary = 'Creates Pods project and gen xcframework.'

      self.description = <<-DESC
        Creates the target for the Pods libraries in the Pods project and the relative support files and gen xcframework.
      DESC

      self.arguments = [
        CLAide::Argument.new('PODSPEC_PATHS', false, true)
      ]

      def initialize(argv)
        super
        @build    = argv.flag?('build', true)
        @local = argv.flag?('local')
        @build_library_for_distribution = argv.flag?('build-library-for-distribution')
        @use_latest = argv.flag?('use-latest', true)
        output_dir = argv.option('output-dir', Pathname.pwd)
        @output_dir = Pathname.new(output_dir).expand_path.join('project_gen/App')
        @allow_warnings      = argv.flag?('allow-warnings', true)
        @clean               = argv.flag?('clean', false)
        @only_subspecs       = argv.option('subspecs', '').split(',')
        @use_frameworks      = !argv.flag?('use-libraries')
        @use_modular_headers = argv.flag?('use-modular-headers', true)
        @use_static_frameworks = argv.flag?('use-static-frameworks')
        @source_urls         = argv.option('sources', Pod::TrunkSource::TRUNK_REPO_URL).split(',')
        @platforms           = argv.option('platforms', '').split(',')
        @swift_version       = argv.option('swift-version', nil)
        @include_podspecs    = argv.option('include-podspecs', '').split(',').map { |path| Pathname.new(path).expand_path }
        @external_podspecs   = argv.option('external-podspecs', '').split(',').map { |path| Pathname.new(path).expand_path }
        @podspecs_paths      = argv.arguments!
        @configuration       = argv.option('configuration', nil)
      end

      def validate!
        super
      end

      # help
      def self.options
        [
          ['--no-build', 'Is or is not to build xcframework'],
          ['--build-library-for-distribution', ' Enables BUILD_LIBRARY_FOR_DISTRIBUTION'],
          ['--use-latest', 'When multiple dependencies with different sources, use latest.'],
          ['--local', 'podpsecs is local or not'],
          ['--output-dir=/project/dir/', 'Gen output dir'],
          ['--allow-warnings', 'Gen even if warnings are present'],
          ['--subspecs=NAME/NAME', 'Gen only the given subspecs'],
          ['--no-clean', 'Gen leaves the build directory intact for inspection'],
          ['--use-libraries', 'Gen uses static libraries to install the spec'],
          ['--use-modular-headers', 'Gen uses modular headers during installation'],
          ['--use-static-frameworks', 'Gen uses static frameworks during installation'],
          ["--sources=#{Pod::TrunkSource::TRUNK_REPO_URL}", 'The sources from which to pull dependent pods ' \
            "(defaults to #{Pod::TrunkSource::TRUNK_REPO_URL}). Multiple sources must be comma-delimited"],
          ['--platforms=ios,macos', 'Gen against specific platforms (defaults to all platforms supported by the ' \
            'podspec). Multiple platforms must be comma-delimited'],
          ['--swift-version=VERSION', 'The `SWIFT_VERSION` that should be used to gen the spec. ' \
           'This takes precedence over the Swift versions specified by the spec or a `.swift-version` file'],
          ['--include-podspecs=**/*.podspec', 'Additional ancillary podspecs which are used for gening via :path'],
          ['--external-podspecs=**/*.podspec', 'Additional ancillary podspecs which are used for gening '\
            'via :podspec. If there are --include-podspecs, then these are removed from them'],
          ['--configuration=CONFIGURATION', 'Build using the given configuration (defaults to Release)']
        ].concat(super)
      end

      def run
        generator = ProjectGenerator.new(@source_urls, @platforms)
        generator.local          = @local
        generator.no_clean       = !@clean
        generator.use_latest = @use_latest
        generator.allow_warnings = @allow_warnings
        generator.only_subspecs   = @only_subspecs
        generator.use_frameworks = @use_frameworks
        generator.use_modular_headers = @use_modular_headers
        generator.use_static_frameworks = @use_static_frameworks
        generator.swift_version = @swift_version
        generator.include_podspecs = @include_podspecs
        generator.external_podspecs = @external_podspecs
        if @local
          generator.include_podspecs += podspecs_to_gen
          generator.include_podspecs.uniq!
        else
          generator.external_podspecs += podspecs_to_gen
          generator.external_podspecs.uniq!
        end
        if generator.include_podspecs.empty? && generator.external_podspecs.empty?
          results = Results.new
          results.error('gen', 'Unable to find podspecs in the working dir. Is local or not local?')
          results.print_results
        else
          generator.configuration = @configuration
          xc_gen = ProjectGen::XcframeworkGen.new(generator)
          xc_gen.generate_xcframework(@output_dir, build: @build, build_library_for_distribution: @build_library_for_distribution)
        end
      end

      private

      # !@group Private helpers

      # @return [Pathname] The path of the podspec found in the current
      #         working directory.
      #
      # @raise  If no podspec is found.
      # @raise  If multiple podspecs are found.
      #
      def podspecs_to_gen
        if @podspecs_paths.empty?
          Pathname.glob(Pathname.pwd.join('*.podspec{.json,}'))
        else
          Array(@podspecs_paths).map { |path| Pathname.new(path).expand_path }
        end
      end
    end
  end
end
