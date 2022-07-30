RSpec.describe 'xcframework gen' do
  podspecs = Pathname.glob(File.expand_path('./Resources/AFNetworking-master', __dir__) + '/*.podspec{.json,}')

  it 'gen' do
    # h
    ProjectGen::Command.run(['gen', "--output-dir=#{File.expand_path('./Resources/output', __dir__)}", podspecs.join(',')])
  end
end
