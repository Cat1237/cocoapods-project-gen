module ProjectGen
  require 'cocoapods'
  require 'pathname'
  require 'claide'
  require 'cocoapods-project-gen/gem_version'
  # autoload registers a file path to be loaded the first time
  # that a specified module or class is accessed in the namespace of the calling module or class.
  autoload :Command, 'cocoapods-project-gen/command/command'
  autoload :ProjectGenerator, 'cocoapods-project-gen/gen/project_gen'
  autoload :XcframeworkGen, 'cocoapods-project-gen/gen/xcframework_gen'
  autoload :Constants, 'cocoapods-project-gen/gen/constants'
  autoload :Utils, 'cocoapods-project-gen/gen/utils'
  autoload :Results, 'cocoapods-project-gen/gen/results'
end
