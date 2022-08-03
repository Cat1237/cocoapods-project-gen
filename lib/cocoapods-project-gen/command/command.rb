# frozen_string_literal: true

# The primary namespace for Gen.
module ProjectGen
  require 'colored2'
  require 'claide'
  # The primary Command for Gen.
  class Command < CLAide::Command
    require 'cocoapods-project-gen/command/gen'

    self.abstract_command = false
    self.command = 'xcframework'
    self.version = VERSION
    self.description = 'Creates Pods project and gen xcframework.'
    self.plugin_prefixes = %w[claide gen]

    def initialize(argv)
      super
      return if ansi_output?

      Colored2.disable!
      String.send(:define_method, :colorize) { |string, _| string }
    end
  end
end
