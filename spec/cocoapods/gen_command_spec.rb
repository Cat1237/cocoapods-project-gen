RSpec.describe 'xcframework gen' do
  podspecs = Pathname.glob(File.expand_path('./Resources/AFNetworking-master', __dir__) + '/*.podspec{.json,}')
  it 'gen' do
    # h
    # , '--use-libraries'
    # , '--no-local',
    # Dir.chdir('/Users/ws/Desktop/VIP课程/mm')
    vs = ProjectGen::Command.run(['gen', '--no-local', *podspecs,
                                  "--output-dir=#{File.expand_path('./Resources/output', __dir__)}"])
    vs.each_pair do |key ,value|
      zip_path = value.join("#{value.basename}.zip")
      ProjectGen::Utils.zip(value, zip_path)
    end
  end
end
