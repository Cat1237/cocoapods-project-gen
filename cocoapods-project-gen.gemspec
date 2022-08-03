# encoding: UTF-8
require File.expand_path('../lib/cocoapods-project-gen/gem_version', __FILE__)

Gem::Specification.new do |spec|
  spec.name          = "cocoapods-project-gen"
  spec.version       = ProjectGen::VERSION
  spec.authors       = ['Cat1237']
  spec.email         = ['wangson1237@outlook.com']

  spec.summary       = 'cocoapods project gen.'
  spec.description   = %(
    cocoapods project gen
  ).strip.gsub(/\s+/, ' ')
  spec.homepage      = 'https://github.com/Cat1237/cocoapods-project-gen.git'
  spec.license       = 'MIT'
  spec.files         = %w[README.md LICENSE] + Dir['lib/**/*.rb']
  spec.require_paths = ['lib']
  spec.executables   = %w[xcframework]

  spec.add_runtime_dependency 'cocoapods', '~> 1.11.3'
  spec.add_development_dependency 'rspec', '>= 3.0'
  spec.required_ruby_version = '>= 2.6'
end
