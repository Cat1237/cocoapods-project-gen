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
    # @param [Bool] Build xcframework.
    #
    def generate_xcframework(work_dir, configuration = nil, build: true, build_library_for_distribution: false)
      app_root = Pathname.new(work_dir).expand_path
      o_value = nil
      @project_gen.generate!(app_root) do |platforms, pod_targets, no_clean, fail_fast|
        if build
          bm = BuildManager.new(app_root, no_clean: no_clean, fail_fast: fail_fast)
          o_value = bm.create_xcframework_products!(platforms, pod_targets, configuration, build_library_for_distribution: build_library_for_distribution)
        else
          o_value = pod_targets
        end
      end
      o_value
    end
  end
end
