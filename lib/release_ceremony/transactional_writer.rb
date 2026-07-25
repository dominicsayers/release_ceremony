# frozen_string_literal: true

require 'fileutils'
require 'tempfile'

module ReleaseCeremony
  # Replaces a set of files atomically: every replacement and a backup of
  # every original are staged as sibling temporary files first, so a failure
  # while installing can restore the originals.
  class TransactionalWriter
    Artifact = Struct.new(:target, :replacement, :backup, keyword_init: true)

    def initialize(renamer: File.method(:rename))
      @renamer = renamer
    end

    def write(changes)
      artifacts = stage_changes(changes)
      install(artifacts)
      true
    ensure
      cleanup(artifacts || [])
    end

    private

    attr_reader :renamer

    def stage_changes(changes)
      artifacts = {}
      changes.each { |target, contents| artifacts[target] = stage_change(target, contents) }
      artifacts.values
    rescue SystemCallError, IOError => e
      cleanup(artifacts.values)
      raise Error, "Could not stage release files: #{e.message}"
    end

    def stage_change(target, contents)
      mode = File.stat(target).mode & 0o7777
      replacement = stage_file(target, contents, mode)
      backup = stage_file(target, File.binread(target), mode)
      Artifact.new(target: target, replacement: replacement, backup: backup)
    rescue SystemCallError, IOError
      cleanup_tempfiles([replacement, backup].compact)
      raise
    end

    def stage_file(target, contents, mode)
      tempfile = Tempfile.new([".#{File.basename(target)}.release-", '.tmp'], File.dirname(target))
      tempfile.binmode
      tempfile.write(contents)
      tempfile.flush
      tempfile.close
      File.chmod(mode, tempfile.path)
      tempfile
    rescue SystemCallError, IOError
      cleanup_tempfiles([tempfile].compact)
      raise
    end

    def install(artifacts)
      artifacts.each { |artifact| renamer.call(artifact.replacement.path, artifact.target) }
    rescue SystemCallError, IOError => e
      raise installation_error(e, rollback(artifacts))
    end

    def rollback(artifacts)
      artifacts.filter_map do |artifact|
        renamer.call(artifact.backup.path, artifact.target)
        nil
      rescue SystemCallError, IOError => e
        "#{artifact.target}: #{e.message}"
      end
    end

    def installation_error(cause, rollback_errors)
      message = "Could not install release files: #{cause.message}"
      if rollback_errors.empty?
        Error.new("#{message}; original release files were restored")
      else
        details = rollback_errors.join(', ')
        Error.new("#{message}; rollback failed for #{details}; release files may be inconsistent")
      end
    end

    def cleanup(artifacts)
      tempfiles = artifacts.flat_map { |artifact| [artifact.replacement, artifact.backup] }
      cleanup_tempfiles(tempfiles)
    end

    def cleanup_tempfiles(tempfiles)
      tempfiles.each do |tempfile|
        tempfile.close
        FileUtils.rm_f(tempfile.path)
      rescue SystemCallError, IOError
        nil
      end
    end
  end
end
