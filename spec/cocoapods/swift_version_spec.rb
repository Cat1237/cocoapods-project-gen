RSpec.describe 'swift version' do
  it 'gen' do
    podspecs = Pathname.glob(File.expand_path('./Resources/Specs', __dir__) + '/*.podspec{.json,}')
    local_podspecs = Pathname.glob(File.expand_path('./Resources/Specs/local/**',
                                                    __dir__) + '/*.podspec{.json,}').join(',')
    no_local_podspecs = Pathname.glob(File.expand_path('./Resources/Specs/no_local/',
                                                       __dir__) + '**/*.podspec{.json,}').join(',')
    out_put = File.expand_path('./Resources/output', __dir__)
    vs = ProjectGen::Command.run(['gen', '--no-use-modular-headers', '--swift-version=5.5',
                                  '--sources=https://github.com/CocoaPods/Specs.git', *podspecs, "--include-podspecs=#{local_podspecs}", "--external-podspecs=#{no_local_podspecs}", "--output-dir=#{out_put}", '--subspecs=AFNetworking/UIKit,AFNetworking/Reachability,Texture/Core,Textur'])
    vs = ProjectGen::Command.run(['gen', '--no-use-modular-headers', '-swift-version=5.0', '--clean',
                                  '--sources=https://github.com/CocoaPods/Specs.git', *podspecs, "--include-podspecs=#{local_podspecs}", "--external-podspecs=#{no_local_podspecs}", "--output-dir=#{out_put}", '--subspecs=AFNetworking/UIKit,AFNetworking/Reachability,Texture/Core,Texture/Yoga,TextNode2'])
    p vs
  end
end
