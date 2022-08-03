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
        @build = argv.flag?('build', true)
        @local = argv.flag?('local', true)
        @output_dir = File.join(argv.option('output-dir', Pathname.pwd), 'project_gen/App')
        @allow_warnings      = argv.flag?('allow-warnings', true)
        @clean               = argv.flag?('clean', false)
        @subspecs            = argv.flag?('subspecs', true)
        @only_subspec        = argv.option('subspec')
        @use_frameworks      = !argv.flag?('use-libraries')
        @use_modular_headers = argv.flag?('use-modular-headers', true)
        @use_static_frameworks = argv.flag?('use-static-frameworks')
        @source_urls         = argv.option('sources', Pod::TrunkSource::TRUNK_REPO_URL).split(',')
        @platforms           = argv.option('platforms', '').split(',')
        @swift_version       = argv.option('swift-version', nil)
        @include_podspecs    = argv.option('include-podspecs', '').split(',')
        @external_podspecs   = argv.option('external-podspecs', '').split(',')
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
          ['--no-local', 'podpsecs is local or not'],
          ['--output-dir=<path>', 'Gen output dir'],
          ['--allow-warnings', 'Gen even if warnings are present'],
          ['--subspec=NAME', 'Gen only the given subspec'],
          ['--no-subspecs', 'Gen skips validation of subspecs'],
          ['--no-clean', 'Gen leaves the build directory intact for inspection'],
          ['--use-libraries', 'Gen uses static libraries to install the spec'],
          ['--use-modular-headers', 'Gen uses modular headers during installation'],
          ['--use-static-frameworks', 'Gen uses static frameworks during installation'],
          ["--sources=#{Pod::TrunkSource::TRUNK_REPO_URL}", 'The sources from which to pull dependent pods ' \
            "(defaults to #{Pod::TrunkSource::TRUNK_REPO_URL}). Multiple sources must be comma-delimited"],
          ['--platforms=ios,macos', 'Gen against specific platforms (defaults to all platforms supported by the ' \
            'podspec). Multiple platforms must be comma-delimited'],
          ['--private', 'Gen skips checks that apply only to public specs'],
          ['--swift-version=VERSION', 'The `SWIFT_VERSION` that should be used to gen the spec. ' \
           'This takes precedence over the Swift versions specified by the spec or a `.swift-version` file'],
          ['--include-podspecs=**/*.podspec', 'Additional ancillary podspecs which are used for gening via :path'],
          ['--external-podspecs=**/*.podspec', 'Additional ancillary podspecs which are used for gening '\
            'via :podspec. If there are --include-podspecs, then these are removed from them'],
          ['--configuration=CONFIGURATION', 'Build using the given configuration (defaults to Release)']
        ].concat(super)
      end

      def run
        generator = ProjectGenerator.new(podspecs_to_gen[0], @source_urls, @platforms)
        generator.local          = @local
        generator.no_clean       = !@clean
        generator.allow_warnings = @allow_warnings
        generator.no_subspecs    = !(!@subspecs || @only_subspec)
        generator.only_subspec   = @only_subspec
        generator.use_frameworks = @use_frameworks
        generator.use_modular_headers = @use_modular_headers
        generator.use_static_frameworks = @use_static_frameworks
        generator.ignore_public_only_results = @private
        generator.swift_version = @swift_version
        generator.test_specs = @test_specs
        generator.include_podspecs = @include_podspecs
        generator.external_podspecs = @external_podspecs
        if @local
          generator.include_podspecs += podspecs_to_gen
          generator.include_podspecs.uniq!
        else
          generator.external_podspecs += podspecs_to_gen
          generator.external_podspecs.uniq!
        end
        generator.configuration = @configuration
        xc_gen = ProjectGen::XcframeworkGen.new(generator)
        xc_gen.generate_xcframework(@output_dir, build: @build)
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
        if !@podspecs_paths.empty?
          Array(@podspecs_paths)
        else
          podspecs = Pathname.glob(Pathname.pwd + '*.podspec{.json,}')

          if podspecs.count.zero?
            podspecs << if @local
                          @include_podspecs[0]
                        else
                          @external_podspecs[0]
                        end
            raise Informative, 'Unable to find a podspec in the working.' if podspecs.count.zero?
          end
          podspecs
        end
      end
    end
  end
end
