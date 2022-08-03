require 'cocoapods'

module ProjectGen
  class BuildManager
    require 'cocoapods-project-gen/gen/build/xcode_build'
    require 'cocoapods-project-gen/gen/product'
    require 'cocoapods-project-gen/gen/build/headers_store'

    attr_reader :root

    def initialize(app_root, root = nil, no_clean: true)
      @root = root.nil? ? app_root : root
      @app_root = app_root
      @no_clean = no_clean
    end

    def product_dir
      Pathname.new(root.parent).join('./project_gen_products').expand_path
    end

    def archive_dir
      Pathname.new(root).join('./project_gen_archive').expand_path
    end

    # Integrates the user projects associated with the {TargetDefinitions}
    # with the Pods project and its products.
    #
    # @return [void]
    #
    def create_xcframework_products!(platforms, pod_targets, configuration = nil)
      ts = pod_targets.values.flatten
      $stdout.print '***'.green
      $stdout.print 'Start Archiving...'
      $stdout.puts ''
      platform_archive_paths = Hash[platforms.map do |platform|
        archive_paths = compute_archive_paths(platform, ts, configuration)
        [platform.name, archive_paths]
      end]
      output = Hash[pod_targets.map do |key, targets|
        products = targets.map do |target|
          Product.new(target, product_dir, root.parent, platform_archive_paths[target.platform.name])
        end
        ps = Products.new(key, products)
        ps.create_bin_products
        ps.add_pod_targets_file_accessors_paths
        [key, ps.product_path]
      end]
      FileUtils.rm_rf(@root) unless @no_clean
      output
    end

    private

    def compute_archive_paths(platform, pod_targets, configuration)
      sdks = Constants.sdks(platform.name)
      archive_paths_by_platform(sdks, platform, pod_targets, configuration)
    end

    def archive_paths_by_platform(sdks, platform, pod_targets, configuration)
      sdks.map do |sdk|
        args = %w[BUILD_LIBRARY_FOR_DISTRIBUTION=YES]
        args += %W[-destination generic/platform=#{Constants::SDK_DESTINATION[sdk]}]
        args += %W[-configuration #{configuration}] unless configuration.nil?
        args += %W[-sdk #{sdk}]
        pod_project_path = File.expand_path('./Pods/Pods.xcodeproj', @app_root)
        archive_root = archive_dir.join(sdk.to_s)
        archive_path = archive_root.join('Pods-App.xcarchive')
        error = XcodeBuild.archive?(args, pod_project_path, "Pods-App-#{platform.name}", archive_path)
        next if error

        print_pod_archive_infos(sdk, archive_path)
        library_targets = pod_targets.select(&:build_as_library?)
        library_targets.each do |target|
          rename_library_product_name(target, archive_path)
          archive_headers_path = archive_root.join(target.pod_name)
          link_headers(target, archive_headers_path)
        end
        archive_path
      end
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
        build_headers.add_files(root_name, module_headers.children) if module_headers.exist?
      end
    end

    # Prints the list of specs & pod cache dirs for a single pod name.
    #
    # This output is valid YAML so it can be parsed with 3rd party tools
    #
    def print_pod_archive_infos(sdk, archive_path)
      $stdout.puts('  - Archive: ')
      $stdout.puts("    Type:    #{sdk}")
      $stdout.puts("    path:    #{archive_path}")
    end
  end
end
