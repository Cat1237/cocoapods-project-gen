RSpec.describe 'gen' do
  it 'gen' do
    podspecs = Pathname.glob(File.expand_path('./Resources/Specs', __dir__) + '/*.podspec{.json,}')
    local_podspecs = Pathname.glob(File.expand_path('./Resources/Specs/local/**',
                                                    __dir__) + '/*.podspec{.json,}')
    no_local_podspecs = Pathname.glob(File.expand_path('./Resources/Specs/no_local/',
                                                       __dir__) + '**/*.podspec{.json,}')
    out_put = File.expand_path('./Resources/output', __dir__)
    generator = ProjectGen::ProjectGenerator.new(%w[https://github.com/CocoaPods/Specs.git], %i[ios macos])
    # generator.local = true
    # generator.no_subspecs = true
    # generator.only_subspecs = nil
    # generator.no_clean       = false
    # generator.allow_warnings = true
    # generator.use_frameworks = product_type == :dynamic_framework
    # generator.use_static_frameworks = true
    generator.use_frameworks = false

    # generator.include_podspecs = podspecs
    generator.configuration = 'Debug'
    # generator.use_modular_headers = use_modular_headers
    generator.swift_version = '5.0'
    generator.external_podspecs = no_local_podspecs + podspecs
    generator.generate!(out_put)
  end
end
