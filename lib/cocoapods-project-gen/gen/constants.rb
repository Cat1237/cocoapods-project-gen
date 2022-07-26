module ProjectGen
  # This modules groups all the constants known to .
  #
  module Constants
    PRODUCT_DIR = 'Products'.freeze

    # The default version of Swift to use when linting pods
    #
    DEFAULT_SWIFT_VERSION = '4.0'.freeze

    # The valid platforms for linting
    #
    VALID_PLATFORMS = Pod::Platform.all.freeze

    COPY_LIBRARY_SWIFT_HEADERS = 'Copy-Library-Swift-Headers'.freeze

    # Whether the platform with the specified name is valid
    #
    # @param  [Platform] platform
    #         The platform to check
    #
    # @return [Boolean] True if the platform is valid
    #
    def self.valid_platform?(platform)
      VALID_PLATFORMS.any? { |p| p.name == platform.name }
    end

    def self.sdks(platform_name)
      case platform_name
      when :osx, :macos
        %i[macosx]
      when :ios
        %i[iphonesimulator iphoneos]
      when :watchos
        %i[watchsimulator watchos]
      when :tvos
        %i[appletvsimulator appletvos]
      end
    end

    # @return [Hash] The extensions or the various product UTIs.
    #
    PRODUCT_UTI_EXTENSIONS = {
      framework: 'framework',
      dynamic_framework: 'dynamic_framework',
      dynamic_library: 'dylib',
      static_library: 'a',
      bundle: 'bundle'
    }.freeze

    SDK_ARCHS = {
      iphonesimulator: %w[x86_64 arm64 i386],
      iphoneos: %w[arm64],
      watchos: %w[armv7k arm64_32],
      watchsimulator: %w[x86_64 arm64],
      appletvos: %w[x86_64 arm64],
      appletvsimulator: %w[x86_64 arm64],
      macosx: %w[x86_64 arm64]
    }.freeze

    SDK_DESTINATION = {
      iphonesimulator: 'iOS Simulator',
      iphoneos: 'iOS',
      watchos: 'watchOS',
      watchsimulator: 'watchOS Simulator',
      appletvos: 'tvOS',
      appletvsimulator: 'tvOS Simulator',
      macosx: 'macOS'
    }.freeze
  end
end
