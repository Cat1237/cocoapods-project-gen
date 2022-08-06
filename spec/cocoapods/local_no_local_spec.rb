RSpec.describe 'gen' do
  it 'local or not local gen' do
    podspecs = Pathname.glob(File.expand_path('./Resources/Specs', __dir__) + '/*.podspec{.json,}')
    local_podspecs = Pathname.glob(File.expand_path('./Resources/Specs/local/**', __dir__) + '/*.podspec{.json,}').join(',')
    no_local_podspecs = Pathname.glob(File.expand_path('./Resources/Specs/no_local/', __dir__) + '**/*.podspec{.json,}').join(',')
    out_put = File.expand_path('./Resources/output', __dir__)
    vs = ProjectGen::Command.run(['gen', '--use-libraries', '--build-library-for-distribution', '--sources=https://github.com/CocoaPods/Specs.git', *podspecs, "--include-podspecs=#{local_podspecs}", "--external-podspecs=#{no_local_podspecs}", "--output-dir=#{out_put}"])
    p vs
  end
end
