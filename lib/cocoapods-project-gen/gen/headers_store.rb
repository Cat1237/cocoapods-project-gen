require 'fileutils'
require 'cocoapods/sa'

module ProjectGen
  # Provides support for managing a header directory. It also keeps track of
  # the header search paths.
  #
  class HeadersStore
    SEARCH_PATHS_KEY = Struct.new(:platform_name, :target_name, :use_modular_headers)

    # @return [Pathname] the absolute path of this header directory.
    #
    def root(source: false)
      root = if source
               sandbox.sources_root
             else
               sandbox.headers_root
             end

      root + @relative_path
    end

    # @return [Sandbox] the sandbox where this header directory is stored.
    #
    attr_reader :sandbox

    # @param  [Sandbox] @see #sandbox
    #
    # @param  [String] relative_path
    #         the relative path to the sandbox root and hence to the Pods
    #         project.
    #
    # @param  [Symbol] visibility_scope
    #         the header visibility scope to use in this store. Can be `:private` or `:public`.
    #
    def initialize(sandbox, relative_path, visibility_scope)
      @sandbox       = sandbox
      @relative_path = relative_path
      @search_paths  = []
      @search_paths_cache = {}
      @visibility_scope = visibility_scope
    end

    #-----------------------------------------------------------------------#

    # @!group Adding headers

    # Adds headers to the directory.
    #
    # @param  [Pathname] namespace
    #         the path where the header file should be stored relative to the
    #         headers directory.
    #
    # @param  [Array<Pathname>] relative_header_paths
    #         the path of the header file relative to the Pods project
    #         (`PODS_ROOT` variable of the xcconfigs).
    #
    # @note   This method does _not_ add the files to the search paths.
    #
    # @return [Array<Pathname>]
    #
    def add_files(namespace, relative_header_paths, ln: false, source: false)
      root(source: source).join(namespace).mkpath unless relative_header_paths.empty?
      relative_header_paths.map do |relative_header_path|
        add_file(namespace, relative_header_path, ln: ln, mkdir: false, source: source)
      end
    end

    # Adds a header to the directory.
    #
    # @param  [Pathname] namespace
    #         the path where the header file should be stored relative to the
    #         headers directory.
    #
    # @param  [Pathname] relative_header_path
    #         the path of the header file relative to the Pods project
    #         (`PODS_ROOT` variable of the xcconfigs).
    #
    # @note   This method does _not_ add the file to the search paths.
    #
    # @return [Pathname]
    #
    def add_file(namespace, relative_header_path, ln: false, mkdir: true, source: false)
      namespaced_path = root(source: source) + namespace
      namespaced_path.mkpath if mkdir

      absolute_source = (sandbox.root + relative_header_path)
      source = absolute_source.relative_path_from(namespaced_path)
      if ln
        if Gem.win_platform?
          FileUtils.ln(absolute_source, namespaced_path, force: true)
        else
          FileUtils.ln_sf(source, namespaced_path)
        end
      else
        FileUtils.cp_r(absolute_source, namespaced_path)
      end
      namespaced_path + relative_header_path.basename
    end
  end
end
