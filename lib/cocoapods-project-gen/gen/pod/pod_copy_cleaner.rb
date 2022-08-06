module ProjectGen
  class PodDirCopyCleaner
    def initialize(podspecs)
      @podspecs = podspecs
    end

    # Copies the `source` directory to `destination`, cleaning the directory
    # of any files unused by `spec`.
    #
    # @return [Void]
    #
    def copy_and_clean(root, sandbox)
      @podspecs.each do |spec|
        destination = root + spec.name
        source = sandbox.pod_dir(spec.name)
        specs_by_platform = group_subspecs_by_platform(spec)
        destination.parent.mkpath
        FileUtils.rm_rf(destination)
        copy(source, destination, specs_by_platform)
      end
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
        specs.flat_map do |spec|
          Pod::Sandbox::FileAccessor.new(path_list, spec.consumer(platform))
        end
      end
      used_files = Pod::Sandbox::FileAccessor.all_files(file_accessors)
      used_files.each do |path|
        path = Pathname(path)
        n_path = destination.join(path.relative_path_from(source))
        n_path.dirname.mkpath
        FileUtils.cp_r(path, n_path.dirname)
      end
    end
  end
end
