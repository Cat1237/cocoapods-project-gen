# cocoapods-project-gen

[![License MIT](https://img.shields.io/badge/license-MIT-green.svg?style=flat)](https://raw.githubusercontent.com/Cat1237/cocoapods-project-gen/main/LICENSE)&nbsp;

A gem which can gen cocoapods project.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'cocoapods-project-gen'
```

And then execute:

```shell
# bundle install
$ bundle install
```

Or install it yourself as:

```shell
# gem install
$ gem install cocoapods-project-gen
```
### Quickstart

To begin gen an cocoapods project start by create an `ProjectGenerator`:

```ruby
require 'cocoapods-project-gen'
podspecs = Pathname.glob(File.expand_path("./Resources/AFNetworking-master", __dir__) + '/*.podspec{.json,}')
out_put = File.expand_path("./Resources/output", __dir__)
gen = ProjectGen::ProjectGenerator.new_from_local(podspecs, [])
gen.generate!(out_put) do |platforms, pod_targets, validated|
    p platforms, pod_targets, validated
end
```

or use this way:

```ruby
require 'cocoapods-project-gen'

product_type = :dynamic_framework
use_module = true
include_podspecs = []
swift_version = '4.2'
configuration = :release
generator = ProjectGen::ProjectGenerator.new(include_podspecs.first, @sources, @platforms)
generator.local = false
generator.no_clean       = false
generator.allow_warnings = true
generator.no_subspecs    = true
generator.only_subspec   = false
generator.use_frameworks = product_type == :dynamic_framework
generator.use_static_frameworks = product_type == :framework
generator.use_modular_headers = use_module
generator.skip_import_validation = true
generator.external_podspecs = include_podspecs.drop(1)
generator.swift_version = swift_version
generator.configuration = configuration
generator.skip_tests = true
begin
    generator.generate!(spec_root) do |platform, pod_targets, validated|
        raise 'Could not generator App.xcodeproj' unless validated

    end
rescue StandardError => e
    raise Pod::Informative, "The `#{@include_podspecs.join(' ')}` specification does not validate." \
                    "\n\n#{e.message}"
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at [yaml-vfs](https://github.com/Cat1237/cocoapods-project-gen). This project is intended to be a safe, welcoming space for collaboration.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the yaml-vfs project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/Cat1237/cocoapods-project-gen/main/CODE_OF_CONDUCT.md).
