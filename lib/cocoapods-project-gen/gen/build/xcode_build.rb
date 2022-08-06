require 'cocoapods/executable'

module ProjectGen
  module XcodeBuild

    def self.archive?(args, project_path, scheme, archive_path)
      command = %w[archive -showBuildTimingSummary]
      command += args
      command += %W[-project #{project_path} -scheme #{scheme} -archivePath #{archive_path}]
      command += %w[SKIP_INSTALL=NO]
      results = Results.new
      output = begin
        Pod::Executable.execute_command('xcodebuild', command, true)
      rescue StandardError => e
        message = 'Returned an unsuccessful exit code.'
        results.error('xcodebuild', message)
        e.message
      end
      results.translate_xcodebuild_output_to_messages(output)
      return false unless results.result_type == :error

      results.print_results
      true
    end

    def self.create_xcframework?(args, output_path)
      command = %w[-create-xcframework]
      command += args
      command += %W[-output #{output_path}]

      results = Results.new
      output = begin
        Pod::Executable.execute_command('xcodebuild', command, true)
      rescue StandardError => e
        message = 'Returned an unsuccessful exit code.'
        results.error('xcodebuild', message)
        e.message
      end

      results.translate_xcodebuild_output_to_messages(output)
      return false unless results.result_type == :error

      results.print_results
      true
    end
  end
end
