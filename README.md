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

To begin gen an cocoapods project by opening an podpsec dir, and to your command line with:

```shell
xcframework gen 
```

or

```shell
xcframework gen --output-dir=<xcframework output dir>
```

```shell
xcframework gen --output-dir=<xcframework output dir> **.podspec
```

To begin gen an cocoapods project start by create an `ProjectGenerator`:

```ruby
podspecs = [**.podspec]
ProjectGen::Command.run(['gen', "--output-dir=#{File.expand_path('./Resources/output', __dir__)}", podspecs.join(' ')])
```

or to build for xcframework use this way:

```ruby
require 'cocoapods-project-gen'

product_type = :dynamic_framework
use_module = true
external_podspecs = []
swift_version = '4.2'
configuration = :release
output_dir = <output dir>
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
generator.external_podspecs = external_podspecs.drop(1)
generator.swift_version = swift_version
generator.configuration = configuration
# xcframework gen
xc_gen = ProjectGen::XcframeworkGen.new(generator)
xc_gen.generate_xcframework(output_dir)
```

other option:

```ruby
['--no-build', 'Is or is not to build xcframework'],
['--no-local', 'podpsecs is local or not'],
['--output-dir=<path>', 'Gen output dir'],
['--allow-warnings', 'Gen even if warnings are present'],
['--subspec=NAME', 'Gen only the given subspec'],
['--no-subspecs', 'Gen skips validation of subspecs'],
['--no-clean', 'Gen leaves the build directory intact for inspection'],
['--use-libraries', 'Gen uses static libraries to install the spec'],
['--use-modular-headers', 'Gen uses modular headers during installation'],
['--use-static-frameworks', 'Gen uses static frameworks during installation'],
["--sources=#{Pod::TrunkSource::TRUNK_REPO_URL}", 'The sources from which to pull dependent pods ' \
"(defaults to #{Pod::TrunkSource::TRUNK_REPO_URL}). Multiple sources must be comma-delimited"],
['--platforms=ios,macos', 'Gen against specific platforms (defaults to all platforms supported by the ' \
'podspec). Multiple platforms must be comma-delimited'],
['--private', 'Gen skips checks that apply only to public specs'],
['--swift-version=VERSION', 'The `SWIFT_VERSION` that should be used to gen the spec. ' \
'This takes precedence over the Swift versions specified by the spec or a `.swift-version` file'],
['--include-podspecs=**/*.podspec', 'Additional ancillary podspecs which are used for gening via :path'],
['--external-podspecs=**/*.podspec', 'Additional ancillary podspecs which are used for gening '\
'via :podspec. If there are --include-podspecs, then these are removed from them'],
['--configuration=CONFIGURATION', 'Build using the given configuration (defaults to Release)']
```

## Command Line Tool

Installing the `cocoapods-project-gen` gem will also install one command-line tool `xcframework gen`  which you can use to generate xcframework from podspec.

For more information consult

- `xcframework --help`
- `xcframework gen --help`

## Contributing

Bug reports and pull requests are welcome on GitHub at [cocoapods-project-gen](https://github.com/Cat1237/cocoapods-project-gen). This project is intended to be a safe, welcoming space for collaboration.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the yaml-vfs project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/Cat1237/cocoapods-project-gen/main/CODE_OF_CONDUCT.md).
