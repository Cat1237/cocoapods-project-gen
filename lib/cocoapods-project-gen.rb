module ProjectGen 
   require 'cocoapods'
   require 'cocoapods-project-gen/gem_version'
   # autoload registers a file path to be loaded the first time
   # that a specified module or class is accessed in the namespace of the calling module or class.
   autoload :ProjectGenerator, 'cocoapods-project-gen/gen/project_gen' 
end