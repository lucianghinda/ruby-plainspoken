# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "yaml"
require "open3"

class OpenCodePluginTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def test_package_registers_the_shared_skill_without_overwriting_existing_skills
    package = JSON.parse(File.read(File.join(REPO, "package.json")))
    assert_equal "ruby-plainspoken", package.fetch("name")
    assert_equal "module", package.fetch("type")
    manifest = JSON.parse(File.read(File.join(REPO, ".codex-plugin/plugin.json")))
    assert_equal manifest.fetch("version"), package.fetch("version")

    output, error, status = Open3.capture3("node", "--input-type=module", "-e", <<~JS, chdir: REPO)
      import { pathToFileURL } from 'node:url';
      import fs from 'node:fs';
      const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
      const { default: plugin } = await import(pathToFileURL(`${process.cwd()}/${pkg.main}`));
      const skills = new Map([['unrelated', { id: 'unrelated' }]]);
      const ctx = { skill: { transform: async (fn) => fn({
        get: (id) => skills.get(id),
        add: (skill) => {
          if (skills.has(skill.id)) throw new Error('duplicate skill');
          skills.set(skill.id, skill);
        }
      }) } };
      await plugin.setup(ctx);
      const registered = skills.get('ruby-plainspoken');
      await plugin.setup(ctx);
      if (skills.get('ruby-plainspoken') !== registered) throw new Error('skill replaced');
      const existing = { id: 'ruby-plainspoken', content: 'user override' };
      skills.set(existing.id, existing);
      await plugin.setup(ctx);
      if (skills.get(existing.id) !== existing) throw new Error('override replaced');
      console.log(JSON.stringify({ id: plugin.id, keys: Object.keys(plugin),
        skills: [...skills.keys()], registered }));
    JS
    assert status.success?, error
    result = JSON.parse(output)
    assert_equal "ruby-plainspoken", result.fetch("id")
    assert_equal %w[id setup], result.fetch("keys").sort
    assert_equal %w[unrelated ruby-plainspoken], result.fetch("skills")

    skill_path = File.join(REPO, "skills/ruby-plainspoken/SKILL.md")
    _, frontmatter, content = File.read(skill_path).split(/^---\r?\n/, 3)
    skill = result.fetch("registered")
    assert_equal "ruby-plainspoken", skill.fetch("id")
    assert_equal "ruby-plainspoken", skill.fetch("name")
    assert_equal skill_path, skill.fetch("path")
    assert_equal YAML.safe_load(frontmatter).fetch("description"), skill.fetch("description")
    assert_equal content, skill.fetch("content")
  end
end
