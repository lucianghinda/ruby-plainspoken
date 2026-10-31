# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "yaml"

class PluginPackageTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  PLUGIN_NAME = "ruby-plainspoken"

  def claude_manifest
    @claude_manifest ||= JSON.parse(File.read(File.join(REPO, ".claude-plugin", "plugin.json")))
  end

  def claude_marketplace
    @claude_marketplace ||= JSON.parse(File.read(File.join(REPO, ".claude-plugin", "marketplace.json")))
  end

  def codex_manifest
    @codex_manifest ||= JSON.parse(File.read(File.join(REPO, ".codex-plugin", "plugin.json")))
  end

  def codex_marketplace
    @codex_marketplace ||= JSON.parse(File.read(File.join(REPO, ".agents", "plugins", "marketplace.json")))
  end

  def skill_path
    File.join(REPO, "skills", PLUGIN_NAME, "SKILL.md")
  end

  def skill_frontmatter
    body = File.read(skill_path)
    match = body.match(/\A---\n(.*?)\n---\n/m)
    refute_nil match, "SKILL.md must open with a YAML frontmatter block"

    YAML.safe_load(match[1])
  end

  def test_both_plugin_manifests_declare_the_same_name
    assert_equal PLUGIN_NAME, claude_manifest["name"]
    assert_equal PLUGIN_NAME, codex_manifest["name"]
  end

  def test_both_plugin_manifests_declare_the_same_semantic_version
    assert_match(/\A\d+\.\d+\.\d+\z/, claude_manifest["version"])
    assert_equal claude_manifest["version"], codex_manifest["version"]
  end

  def test_the_readme_documents_the_version_the_manifests_declare
    assert_includes File.read(File.join(REPO, "README.md")), claude_manifest["version"]
  end

  def test_both_plugin_manifests_carry_the_metadata_a_release_needs
    [claude_manifest, codex_manifest].each do |manifest|
      assert manifest["description"].to_s.length > 40, "#{manifest['name']} needs a description a user can judge"
      assert_equal "MIT", manifest["license"]
      refute_nil manifest.dig("author", "name")
      assert_match(%r{\Ahttps://}, manifest["repository"])
    end
  end

  def test_the_plugin_description_names_what_the_plugin_is_for
    %w[Ruby Rails].each do |term|
      assert_includes claude_manifest["description"], term
      assert_includes codex_manifest["description"], term
    end
  end

  def test_the_codex_manifest_points_at_the_shared_skills_directory
    assert_equal "./skills/", codex_manifest["skills"]
  end

  def test_the_claude_marketplace_offers_the_plugin_from_the_repository_root
    entry = claude_marketplace.fetch("plugins").fetch(0)

    assert_equal PLUGIN_NAME, entry["name"]
    assert_equal "./", entry["source"]
    refute_nil claude_marketplace.dig("owner", "name")
  end

  def test_the_codex_marketplace_offers_the_plugin_to_codex
    entry = codex_marketplace.fetch("plugins").fetch(0)

    assert_equal PLUGIN_NAME, entry["name"]
    assert_equal "local", entry.dig("source", "source")
    assert_includes entry.dig("policy", "products"), "CODEX"
  end

  def test_the_codex_marketplace_source_path_resolves_to_the_repository_root
    path = codex_marketplace.fetch("plugins").fetch(0).dig("source", "path")
    resolved = File.realpath(File.join(REPO, path))

    assert_equal File.realpath(REPO), resolved
  end

  def test_the_codex_marketplace_source_path_is_a_symlink_and_not_a_copy
    path = codex_marketplace.fetch("plugins").fetch(0).dig("source", "path")

    assert File.symlink?(File.join(REPO, path)),
           "#{path} must be a symlink to the repository root, so Codex and Claude Code load the same files"
  end

  def test_the_repository_offers_exactly_one_skill
    skills = Dir.glob(File.join(REPO, "skills", "*", "SKILL.md"))

    assert_equal [skill_path], skills
  end

  def test_the_skill_frontmatter_name_matches_its_directory
    assert_equal PLUGIN_NAME, skill_frontmatter.fetch("name")
  end

  def test_the_skill_description_names_the_work_it_applies_to
    description = skill_frontmatter.fetch("description")

    ["Ruby", "Rails", "refactor", "review"].each do |term|
      assert_includes description, term
    end
  end

  def test_the_skill_description_names_the_work_it_does_not_apply_to
    description = skill_frontmatter.fetch("description")

    assert_includes description, "Not for other languages"
  end

  def test_the_skill_description_fits_the_length_a_model_reads
    length = skill_frontmatter.fetch("description").length

    assert_operator length, :>, 200, "too short to separate Ruby work from everything else"
    assert_operator length, :<, 1024, "too long to sit in every session's skill listing"
  end

  def test_every_supporting_file_the_skill_links_to_exists
    body = File.read(skill_path)
    links = body.scan(%r{`(references/[\w./-]+\.md)`}).flatten

    refute_empty links, "the skill must route to its reference file"
    links.uniq.each do |link|
      assert_path_exists File.join(File.dirname(skill_path), link)
    end
  end

  def test_the_skill_keeps_the_detail_out_of_the_active_body
    skill_lines = File.read(skill_path).lines.length
    reference_lines = File.read(File.join(REPO, "skills", PLUGIN_NAME, "references", "ruby-and-rails.md")).lines.length

    assert_operator skill_lines, :<, reference_lines,
                    "detail belongs in the reference, which loads only when a decision needs it"
  end

  def test_the_readme_documents_installing_on_both_agents
    readme = File.read(File.join(REPO, "README.md"))

    assert_includes readme, "claude plugin marketplace add"
    assert_includes readme, "codex plugin marketplace add"
  end
end
