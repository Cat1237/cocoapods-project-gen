require 'cocoapods'

module ProjectGen
  class BuildManager
    require 'cocoapods-project-gen/gen/xcode_build'
    require 'cocoapods-project-gen/gen/product'

    autoload :HeadersStore, 'cocoapods-project-gen/gen/headers_store'

    attr_reader :root

    def initialize(app_root, root = nil, no_clean: true)
      @root = root.nil? ? app_root : root
      @app_root = app_root
      @no_clean = no_clean
    end

    def product_dir
      Pathname.new(root).join('./ProjectGenProducts').expand_path
    end

    def archive_dir
      Pathname.new(root).join('./ProjectGenArchive').expand_path
    end

    # Integrates the user projects associated with the {TargetDefinitions}
    # with the Pods project and its products.
    #
    # @return [void]
    #
    def create_xcframework_products!(platforms, pod_targets, configuration = nil)
      $stdout.puts 'start archiving...'
      ts = pod_targets.values.flatten
      archive_paths = platforms.flat_map do |platform|
        archive_path = compute_archive_paths(platform, ts, configuration)
        archive_path.each { |ap| $stdout.puts "[archive]: #{ap}".green }
        archive_path
      end
      pod_targets.each_pair do |key, value|
        $stdout.puts "start #{key} xcframework..."

        products = Products.new([value[0]], product_dir, archive_paths, root.parent)
        products.create_bin_products
        products.add_pod_targets_file_accessors_paths
      end
      FileUtils.rm_rf(product_dir) unless @no_clean
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
        XcodeBuild.archive(args, pod_project_path, "Pods-App-#{platform.name}", archive_path)
        library_targets = pod_targets.select(&:build_as_library?)
        library_targets.each do |target|
          archive_headers_path = archive_root.join(target.pod_name)
          link_headers(target, archive_headers_path)
        end
        archive_path
      end
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
        build_headers.add_files(root_name, module_headers.children)
        build_headers.root
      end
    end
  end
end
