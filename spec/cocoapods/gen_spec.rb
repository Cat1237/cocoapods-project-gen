RSpec.describe 'gen' do
    it 'project gen' do
        podspecs = Pathname.glob(File.expand_path("./Resources/AFNetworking-master", __dir__) + '/*.podspec{.json,}')
        out_put = File.expand_path("./Resources/output", __dir__)
        gen = ProjectGen::ProjectGenerator.new_from_local(podspecs, [])
        gen.generate!(out_put) do |platforms, pod_targets, validated|
            p platforms, pod_targets, validated
        end
    end
end    
