RSpec.describe 'xcframework gen' do
  podspecs = Pathname.glob(File.expand_path('./Resources/AFNetworking-master', __dir__) + '/*.podspec{.json,}')
  it 'gen' do
    # h
    # , '--use-libraries'
    # , '--no-local',
    # Dir.chdir('/Users/ws/Desktop/VIP课程/mm')
    vs = ProjectGen::Command.run(['gen', '--no-local', '--include-podspecs=/Users/ws/Desktop/VIP课程/工程化实战班/10-组件二进制完结/上课代码/01-xcframework/specs/MJRefresh/MJRefresh.podspec,/Users/ws/Desktop/VIP课程/工程化实战班/10-组件二进制完结/上课代码/01-xcframework/specs/SDWebImage-master/SDWebImage.podspec',
                                  "--output-dir=#{File.expand_path('./Resources/output', __dir__)}"])
    vs.each_pair do |_key, value|
      zip_path = value.join("#{value.basename}.zip")
      ProjectGen::Utils.zip(value, zip_path)
    end
  end
end
