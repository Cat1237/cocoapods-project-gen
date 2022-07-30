require 'cocoapods-project-gen/gen/project_gen'
require 'cocoapods-project-gen/gen/project_builder'
module ProjectGen
  class XcframeworkGen

    def self.new_from_project_gen(project_gen)
      new(project_gen)
    end

    # Initialize a new instance
    #
    # @param [ProjectGenerator] project_gen
    #        Creates the target for the Pods libraries in the Pods project and the
    #        relative support files.
    #
    def initialize(project_gen)
      @project_gen = project_gen
    end

    # Initialize a new instance
    #
    # @param [<Pathname, String>] work_dir 
    #        the temporary directory used by the Generator.
    #
    # @param [Symbol] The name of the build configuration.
    #
    def generate_xcframework(work_dir, configuration = nil)
      app_root = Pathname.new(work_dir)
      @project_gen.generate!(app_root) do |platforms, pod_targets, validated, no_clean|
        raise 'Could not generator App.xcodeproj' unless validated

        bm = BuildManager.new(app_root, no_clean: no_clean)
        bm.create_xcframework_products!(platforms, pod_targets, configuration)
        $stdout.puts 'finish...'
      end
    end
  end
end
