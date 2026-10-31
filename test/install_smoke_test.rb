# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "open3"
require "tmpdir"
require "fileutils"

class InstallSmokeTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  PLUGIN_NAME = "ruby-plainspoken"
  SELECTOR = "#{PLUGIN_NAME}@#{PLUGIN_NAME}"

  def self.command_available?(name)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
       .any? { |directory| File.executable?(File.join(directory, name)) }
  end

  def copy_of_the_repository(directory)
    copy = File.join(directory, "plugin")
    FileUtils.mkdir_p(copy)
    Dir.children(REPO).each do |entry|
      next if [".git", ".remember", "tmp"].include?(entry)

      FileUtils.cp_r(File.join(REPO, entry), copy, preserve: true)
    end

    copy
  end

  def bump_version(copy, version)
    [File.join(copy, ".claude-plugin", "plugin.json"), File.join(copy, ".codex-plugin", "plugin.json")].each do |path|
      manifest = JSON.parse(File.read(path))
      manifest["version"] = version
      File.write(path, "#{JSON.pretty_generate(manifest)}\n")
    end
  end

  def run_command(env, *arguments)
    output, error, status = Open3.capture3(env, *arguments)
    ["#{output}#{error}", status]
  end

  def test_a_clean_claude_code_configuration_installs_the_plugin_and_takes_a_later_version
    skip "claude is not on PATH" unless self.class.command_available?("claude")

    Dir.mktmpdir("install-smoke") do |directory|
      config = File.join(directory, "claude-config")
      FileUtils.mkdir_p(config)
      env = { "CLAUDE_CONFIG_DIR" => config }
      copy = copy_of_the_repository(directory)

      refute_path_exists File.join(config, "plugins"), "the test must start with no plugin cache"

      added, status = run_command(env, "claude", "plugin", "marketplace", "add", copy)
      assert status.success?, "adding the marketplace failed: #{added}"

      installed, status = run_command(env, "claude", "plugin", "install", SELECTOR)
      assert status.success?, "installing the plugin failed: #{installed}"

      listing, = run_command(env, "claude", "plugin", "list")
      assert_includes listing, SELECTOR
      assert_includes listing, "0.1.0"
      assert_includes listing, "enabled"

      details, = run_command(env, "claude", "plugin", "details", SELECTOR)
      assert_match(/Skills \(1\)\s+#{PLUGIN_NAME}/, details, "Claude Code must find exactly the one skill")

      bump_version(copy, "0.2.0")

      updated_marketplace, status = run_command(env, "claude", "plugin", "marketplace", "update", PLUGIN_NAME)
      assert status.success?, "updating the marketplace failed: #{updated_marketplace}"

      updated, status = run_command(env, "claude", "plugin", "update", SELECTOR)
      assert status.success?, "updating the plugin failed: #{updated}"
      assert_includes updated, "0.2.0"

      listing, = run_command(env, "claude", "plugin", "list")
      assert_includes listing, "0.2.0"
    end
  end

  def test_a_clean_codex_configuration_installs_the_plugin_and_finds_the_skill
    skip "codex is not on PATH" unless self.class.command_available?("codex")

    Dir.mktmpdir("install-smoke") do |directory|
      home = File.join(directory, "codex-home")
      FileUtils.mkdir_p(home)
      env = { "CODEX_HOME" => home }
      copy = copy_of_the_repository(directory)

      added, status = run_command(env, "codex", "plugin", "marketplace", "add", copy)
      assert status.success?, "adding the marketplace failed: #{added}"

      installed, status = run_command(env, "codex", "plugin", "add", SELECTOR)
      assert status.success?, "installing the plugin failed: #{installed}"

      listing, = run_command(env, "codex", "plugin", "list")
      assert_includes listing, "installed, enabled"
      assert_includes listing, "0.1.0"

      cached_skill = File.join(home, "plugins", "cache", PLUGIN_NAME, PLUGIN_NAME, "0.1.0",
                               "skills", PLUGIN_NAME, "SKILL.md")
      assert_path_exists cached_skill
      assert_includes File.read(cached_skill), "name: #{PLUGIN_NAME}"
      assert_path_exists File.join(File.dirname(cached_skill), "references", "ruby-and-rails.md")

      bump_version(copy, "0.2.0")

      installed, status = run_command(env, "codex", "plugin", "add", SELECTOR)
      assert status.success?, "reinstalling after the version bump failed: #{installed}"

      listing, = run_command(env, "codex", "plugin", "list")
      assert_includes listing, "0.2.0"
    end
  end

  def test_no_application_gemfile_is_needed_to_install_on_either_agent
    refute_path_exists File.join(REPO, "Gemfile")
    refute_path_exists File.join(REPO, "#{PLUGIN_NAME}.gemspec")
  end
end
