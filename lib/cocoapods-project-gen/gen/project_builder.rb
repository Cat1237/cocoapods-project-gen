require 'cocoapods'

module ProjectGen
  class BuildManager
    require 'cocoapods-project-gen/gen/build/xcode_build'
    require 'cocoapods-project-gen/gen/product'
    require 'cocoapods-project-gen/gen/build/headers_store'

    attr_reader :root

    def initialize(app_root, root = nil, no_clean: true, fail_fast: true)
      @root = root.nil? ? app_root : root
      @app_root = app_root
      @no_clean = no_clean
      @fail_fast = fail_fast
    end

    def product_dir
      Pathname.new(root.parent).join('./project_gen_products').expand_path
    end

    def archives_dir
      Pathname.new(root.parent).join('./project_gen_archives').expand_path
    end

    # Integrates the user projects associated with the {TargetDefinitions}
    # with the Pods project and its products.
    #
    # @return [void]
    #
    def create_xcframework_products!(platforms, pod_targets, configuration = nil, build_library_for_distribution: false)
      ts = pod_targets.values.flatten
      Results.puts '-> Start Archiving...'.green
      platform_archive_paths = Hash[platforms.map do |platform|
        archive_paths = compute_archive_paths(platform, ts, configuration, build_library_for_distribution)
        [platform.name, archive_paths]
      end]
      return if platform_archive_paths.values.flatten.empty?

      output = Hash[pod_targets.map do |key, targets|
        products = targets.map do |target|
          Product.new(target, product_dir, root.parent, platform_archive_paths[target.platform.name])
        end
        ps = Products.new(key, products)
        ps.create_bin_products
        ps.add_pod_targets_file_accessors_paths
        [key, ps.product_path]
      end]
      unless @no_clean
        FileUtils.rm_rf(@app_root)
        FileUtils.rm_rf(archives_dir)
      end
      output
    end

    private

    def compute_archive_paths(platform, pod_targets, configuration, build_library_for_distribution)
      sdks = Constants.sdks(platform.name)
      archive_paths_by_platform(sdks, platform, pod_targets, configuration, build_library_for_distribution)
    end

    def archive_paths_by_platform(sdks, platform, pod_targets, configuration, build_library_for_distribution)
      sdks.map do |sdk|
        args = if build_library_for_distribution
                 %w[BUILD_LIBRARY_FOR_DISTRIBUTION=YES]
               else
                 []
               end
        args += %W[-destination generic/platform=#{Constants::SDK_DESTINATION[sdk]}]
        args += %W[-configuration #{configuration}] unless configuration.nil?
        args += %W[-sdk #{sdk}]
        pod_project_path = File.expand_path('./Pods/Pods.xcodeproj', @app_root)
        archive_root = archives_dir.join(sdk.to_s)
        archive_path = archive_root.join('Pods-App.xcarchive')
        error = XcodeBuild.archive?(args, pod_project_path, "Pods-App-#{platform.string_name}", archive_path)
        break if @fail_fast && error
        next if error

        print_pod_archive_infos(sdk, archive_path)
        library_targets = pod_targets.select(&:build_as_library?)
        library_targets.each do |target|
          rename_library_product_name(target, archive_path)
          archive_headers_path = archive_root.join(target.pod_name)
          link_headers(target, archive_headers_path)
        end
        archive_path
      end.compact
    end

    def rename_library_product_name(target, archive_path)
      return unless target.build_as_library?

      full_archive_path = archive_path.join('Products/usr/local/lib')
      full_product_path = full_archive_path.join(target.static_library_name)
      scope_suffix = target.scope_suffix
      return unless full_product_path.exist? && scope_suffix && target.label.end_with?(scope_suffix)

      label = Utils.remove_target_scope_suffix(target.label, scope_suffix)
      new_full_archive_path = full_archive_path.join("lib#{label}.a")
      File.rename(full_product_path, new_full_archive_path)
    end

    # Creates the link to the headers of the Pod in the sandbox.
    #
    # @return [void]
    #
    def link_headers(target, product_path)
      Pod::UI.message '- Linking headers' do
        # When integrating Pod as frameworks, built Pods are built into
        # frameworks, whose headers are included inside the built
        # framework. Those headers do not need to be linked from the
        # sandbox.
        next if target.build_as_framework? && target.should_build?

        sandbox = Pod::Sandbox.new(product_path)
        build_headers = ProjectGen::HeadersStore.new(sandbox, '', :public)
        pod_target_header_mappings = target.header_mappings_by_file_accessor.values
        public_header_mappings = target.public_header_mappings_by_file_accessor.values
        headers = pod_target_header_mappings + public_header_mappings
        headers.uniq.each do |header_mappings|
          header_mappings.each do |namespaced_path, files|
            hs = build_headers.add_files('', files)
            build_headers.add_files(namespaced_path, hs, ln: true)
          end
        end
        root_name = Pod::Specification.root_name(target.pod_name)
        pod_dir = target.sandbox.sources_root.join(root_name)
        module_headers = pod_dir.join(Constants::COPY_LIBRARY_SWIFT_HEADERS)
        module_paths = build_headers.add_files(root_name, module_headers.children) if module_headers.exist?
        module_paths
      end
    end

    # Prints the list of specs & pod cache dirs for a single pod name.
    #
    # This output is valid YAML so it can be parsed with 3rd party tools
    #
    def print_pod_archive_infos(sdk, archive_path)
      Results.puts("  - Archive: #{sdk}")
      Results.puts("    path:    #{archive_path}")
    end
  end
end
