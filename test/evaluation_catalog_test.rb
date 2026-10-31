# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class EvaluationCatalogTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  EVALS = File.join(REPO, "evals")

  GRADER_TYPES = %w[regex tool_order tool_used file_exists llm baseline].freeze
  KIND_TAGS = %w[trigger behaviour fixture].freeze
  REQUIREMENTS_THE_CASES_MUST_COVER = (2..18).map { |number| "r#{number}" }.freeze

  def case_paths
    @case_paths ||= Dir.glob(File.join(EVALS, "*", "case.yaml")).sort
  end

  def cases
    @cases ||= case_paths.to_h { |path| [path, YAML.safe_load(File.read(path))] }
  end

  def each_case
    cases.each { |path, document| yield(File.basename(File.dirname(path)), document, path) }
  end

  def test_the_catalog_is_not_empty
    refute_empty case_paths
  end

  def test_every_case_is_a_yaml_object
    each_case { |name, document| assert_kind_of Hash, document, "#{name}/case.yaml must be a YAML object" }
  end

  def test_every_case_declares_a_schema_version_this_claude_code_supports
    each_case do |name, document|
      version = document["schema_version"]

      assert_kind_of String, version, "#{name} must declare schema_version as a string"
      assert_equal 1, version.split(".").first.to_i, "#{name} declares a schema_version this binary cannot read"
    end
  end

  def test_every_case_name_matches_its_directory
    each_case { |name, document| assert_equal name, document["name"] }
  end

  def test_case_names_are_unique
    names = cases.values.map { |document| document["name"] }

    assert_equal names.uniq.sort, names.sort
  end

  def test_every_case_says_what_it_proves
    each_case do |name, document|
      assert document["description"].to_s.length > 30, "#{name} must say what it proves"
      assert document["expected_outcome"].to_s.length > 20, "#{name} must state the outcome that passes"
    end
  end

  def test_every_case_carries_exactly_one_kind_tag
    each_case do |name, document|
      kinds = document.fetch("tags", []) & KIND_TAGS

      assert_equal 1, kinds.length, "#{name} carries #{kinds.length} kind tags (#{KIND_TAGS.join(', ')}), it needs one"
    end
  end

  def test_a_guard_tag_is_only_on_cases_that_have_a_baseline
    each_case do |name, document|
      tags = document.fetch("tags", [])
      next unless tags.include?("guard")

      refute_includes tags, "trigger", "#{name} is a trigger case, which has no baseline arm, so it cannot be a guard"
    end
  end

  def test_every_case_names_at_least_one_requirement
    each_case do |name, document|
      requirements = document.fetch("tags", []).grep(/\Ar\d+\z/)

      refute_empty requirements, "#{name} must tag the requirement it serves, for example r6"
    end
  end

  def test_the_catalog_covers_every_requirement_the_skill_is_meant_to_meet
    tagged = cases.values.flat_map { |document| document.fetch("tags", []) }.uniq
    missing = REQUIREMENTS_THE_CASES_MUST_COVER - tagged

    assert_empty missing, "no case covers #{missing.join(', ')}"
  end

  def test_every_case_asks_for_a_run_count_the_runner_accepts
    each_case do |name, document|
      runs = document.fetch("runs")

      assert_kind_of Integer, runs, "#{name} runs must be an integer"
      assert_operator runs, :>, 0, "#{name} runs must be above zero"
      assert_operator runs, :<=, 50, "#{name} runs must be 50 or fewer"
    end
  end

  def test_every_case_has_a_prompt_a_user_could_plausibly_have_typed
    each_case do |name, document|
      prompt = document.dig("execution", "prompt").to_s

      refute_empty prompt.strip, "#{name} must have execution.prompt"
      refute_match(/ruby-plainspoken/, prompt,
                   "#{name} names the skill in its prompt, which cannot test whether the skill would be found")
    end
  end

  def test_every_case_bounds_its_turns_and_time
    each_case do |name, document|
      turns = document.dig("execution", "max_turns")

      assert_kind_of Integer, turns, "#{name} must set execution.max_turns"
      assert_operator turns, :<=, 200, "#{name} max_turns is above the runner's limit"

      seconds = document.dig("execution", "timeout_seconds")
      assert_operator seconds, :<=, 3600, "#{name} timeout_seconds is above the runner's limit" if seconds
    end
  end

  def test_every_case_lets_the_agent_load_a_skill
    each_case do |name, document|
      tools = document.dig("execution", "allowed_tools")

      assert_includes tools.to_a, "Skill", "#{name} must allow the Skill tool or the plugin can never fire"
    end
  end

  def test_every_case_has_at_least_one_grader
    each_case { |name, document| refute_empty document.fetch("graders", []), "#{name} must have a grader" }
  end

  def test_every_grader_declares_a_type_the_runner_knows
    each_case do |name, document|
      document.fetch("graders").each do |grader|
        assert_includes GRADER_TYPES, grader["type"], "#{name} grader #{grader['name']} has an unknown type"
      end
    end
  end

  def test_grader_names_are_unique_within_a_case
    each_case do |name, document|
      names = document.fetch("graders").map { |grader| grader["name"] }

      refute_includes names, nil, "#{name} has a grader with no name"
      assert_equal names.uniq.sort, names.sort, "#{name} has two graders with the same name"
    end
  end

  def test_every_grader_carries_the_fields_its_type_requires
    each_case do |name, document|
      document.fetch("graders").each do |grader|
        label = "#{name} grader #{grader['name']}"

        case grader["type"]
        when "regex"
          refute_nil grader["pattern"], "#{label} needs a pattern"
        when "tool_used"
          refute_nil grader["tool"], "#{label} needs a tool"
          assert grader.key?("min") || grader.key?("max"), "#{label} needs min or max, or it asserts nothing"
        when "file_exists"
          refute_nil grader["path"], "#{label} needs a path"
        when "llm"
          assert grader["criteria"].to_s.length > 40, "#{label} needs concrete pass criteria"
        when "baseline"
          refute_nil grader["baseline_file"], "#{label} needs a baseline_file"
        end
      end
    end
  end

  def test_every_regex_grader_pattern_compiles
    each_case do |name, document|
      document.fetch("graders").select { |grader| grader["type"] == "regex" }.each do |grader|
        Regexp.new(grader["pattern"])
      rescue RegexpError => e
        flunk "#{name} grader #{grader['name']} has an unusable pattern: #{e.message}"
      end
    end
  end

  def test_every_regex_grader_match_mode_is_one_the_runner_accepts
    each_case do |name, document|
      document.fetch("graders").select { |grader| grader["type"] == "regex" }.each do |grader|
        mode = grader["match"]
        next if mode.nil?

        assert_match(/\A(contains|not_contains|count:\d+)\z/, mode,
                     "#{name} grader #{grader['name']} has match #{mode.inspect}")
      end
    end
  end

  def test_every_file_targeted_regex_grader_reads_a_file_the_case_can_produce
    each_case do |name, document, path|
      scaffold = document.dig("context", "scaffold_script")
      next unless scaffold

      fixture_files = fixture_files_for(File.dirname(path), scaffold)
      next if fixture_files.empty?

      expected_new_files = document.fetch("graders")
                                   .select { |grader| grader["type"] == "file_exists" && grader.fetch("exists", true) }
                                   .map { |grader| grader["path"] }

      document.fetch("graders").each do |grader|
        target = grader["target"]
        next unless target.is_a?(Hash) && target["source"] == "file"

        assert_includes fixture_files + expected_new_files, target["path"],
                        "#{name} grader #{grader['name']} reads #{target['path']}, which the fixture does not contain " \
                        "and no file_exists grader in this case requires the agent to create"
      end
    end
  end

  def test_every_fixture_case_has_an_executable_scaffold
    each_case do |name, document, path|
      next unless document.fetch("tags", []).include?("fixture")

      scaffold = document.dig("context", "scaffold_script")
      refute_nil scaffold, "#{name} is tagged fixture, so it needs context.scaffold_script"

      resolved = File.join(File.dirname(path), scaffold)
      assert_path_exists resolved
      assert File.executable?(resolved), "#{resolved} must be executable"
    end
  end

  def test_no_text_only_case_carries_a_scaffold
    each_case do |name, document|
      next if document.fetch("tags", []).include?("fixture")

      assert_nil document.dig("context", "scaffold_script"),
                 "#{name} is not a fixture case, so it must not need a scaffold"
    end
  end

  def test_every_scaffold_copies_a_fixture_that_exists
    each_case do |name, document, path|
      scaffold = document.dig("context", "scaffold_script")
      next unless scaffold

      body = File.read(File.join(File.dirname(path), scaffold))
      referenced = body.scan(%r{\$case_dir/(\.\./fixtures/[\w./-]+)}).flatten

      refute_empty referenced, "#{name} scaffold copies no fixture"
      referenced.each do |relative|
        assert_path_exists File.expand_path(File.join(File.dirname(path), relative))
      end
    end
  end

  def test_the_trigger_cases_include_both_a_positive_and_a_negative_case
    trigger = cases.values.select { |document| document.fetch("tags", []).include?("trigger") }
    tags = trigger.map { |document| document.fetch("tags") }

    assert tags.any? { |list| list.include?("positive") }, "a trigger case must prove the skill fires"
    assert tags.any? { |list| list.include?("negative") }, "a trigger case must prove the skill stays out of the way"
  end

  def test_every_negative_trigger_case_asserts_the_skill_did_not_fire
    cases.each_value do |document|
      next unless (document.fetch("tags", []) & %w[trigger negative]).length == 2

      grader = document.fetch("graders").find { |candidate| candidate["type"] == "tool_used" }

      refute_nil grader, "#{document['name']} must assert on the Skill tool"
      assert_equal "Skill", grader["tool"]
      assert_equal 0, grader["max"], "#{document['name']} must require the skill not to fire at all"
    end
  end

  def test_no_case_directory_is_missing_its_case_file
    directories = Dir.glob(File.join(EVALS, "*")).select { |path| File.directory?(path) }
    directories -= [File.join(EVALS, "fixtures"), File.join(EVALS, "results")]

    directories.each do |directory|
      assert_path_exists File.join(directory, "case.yaml")
    end
  end

  private

  def fixture_files_for(case_dir, scaffold)
    body = File.read(File.join(case_dir, scaffold))
    roots = body.scan(%r{\$case_dir/(\.\./fixtures/[\w./-]+?)(?:/\.)?["\s]}).flatten

    roots.flat_map do |relative|
      root = File.expand_path(File.join(case_dir, relative))
      next [] unless File.directory?(root)

      Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH)
         .select { |path| File.file?(path) }
         .map { |path| path.delete_prefix("#{root}/") }
    end.uniq
  end
end
