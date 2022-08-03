require 'fileutils'

module ProjectGen
  module Utils
    # @return [Bool]
    #
    def self.absolute?(path)
      Pathname(path).absolute? || path.to_s.start_with?('~')
    end

    def self.remove_target_scope_suffix(label, scope_suffix)
      if scope_suffix.nil? || scope_suffix[0] == '.'
        label.delete_suffix(scope_suffix || '')
      else
        label.delete_suffix("-#{scope_suffix}")
      end
    end

    def self.zip(product_path, zip_path)
      product_name = Pathname.new(product_path).basename
      zip_product_name = Pathname.new(zip_path).basename
      FileUtils.rm_rf(zip_path)
      FileUtils.mkdir_p(zip_path.dirname)
      Dir.chdir(product_path) do
        out_put = `pushd #{product_name};zip -qry #{zip_path} *;popd`
        if out_put.downcase.include?('error')
            $stdout.puts(out_put.red)
        else
          $stdout.puts("#{zip_product_name}:".green)
          $stdout.puts("    path:    #{zip_path}".green)
        end
      end
    end
  end
end
