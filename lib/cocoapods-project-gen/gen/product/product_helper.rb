require 'cocoapods/target/pod_target'

module ProjectGen

  require 'delegate'

  class GenTarget < DelegateClass(Pod::PodTarget)
    def initialize(target)
      super(target)
      target.uses_swift?
    end
  end

  module ProductHelper
    
    def version
      root_spec.version
    end

    def label
      target.label
    end

    def scope_suffix
      target.scope_suffix
    end

    def static_library_name
      "lib#{Utils.remove_target_scope_suffix(label, scope_suffix)}.a"
    end

    def pod_dir
      root_name = module_basename
      sandbox.sources_root + root_name
    end

    def build_as_library?
      target.build_as_library?
    end

    def uses_swift?
      target.uses_swift?
    end

    def build_as_framework?
      target.build_as_framework?
    end

    def module_basename 
      Pod::Specification.root_name(pod_name)
    end

    def product_name
      target.product_name
    end

    def pod_name
      target.pod_name
    end

    def product_type
      target.product_type
    end

    def file_accessors
      target.file_accessors
    end

    def sandbox
      target.sandbox
    end

    def xcframework_product_name
      "#{xcframework_name}.xcframework"
    end

    def xcframework_name
      pod_name
    end

    def root_spec
      target.root_spec
    end

    def product_path
      product_root.join("#{module_basename}-#{product_type}-#{version}")
    end

    def xcframework_product_path
      product_path.join(xcframework_product_name)
    end
  end
end
