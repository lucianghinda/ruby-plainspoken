# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "yaml"
require "tmpdir"
require "fileutils"

load File.expand_path("../bin/evaluate", __dir__)

class CodexEvalTest < Minitest::Test
  class FakeJudge
    attr_reader :cost_usd, :calls

    def initialize(votes)
      @votes = votes
      @cost_usd = 0.0
      @calls = []
    end

    def votes(**arguments)
      @calls << arguments
      @votes
    end
  end

  # Stands in for CodexEval::Agent: answers by arm from a table.
  class FakeAgent
    def initialize(answers)
      @answers = answers
    end

    def open = yield(self)

    def run(eval_case, arm)
      answer = @answers.fetch([eval_case.name, arm])
      events = arm == "with" ? [{ "item" => { "type" => "command_execution", "command" => "cat /c/ruby-plainspoken/SKILL.md" } }] : []
      yield CodexEval::Run.new(last_message: answer, events:, workdir: nil, diff: nil, error: nil)
    end
  end

  def eval_case(graders:, kind: "behaviour", name: "some-case", tags: nil)
    CodexEval::EvalCase.new(name:, tags: tags || [kind, "r2"], prompt: "Review this.", runs: 1,
                            timeout: 30, scaffold: nil, graders:)
  end

  def a_run(last_message: "", events: [], workdir: nil, diff: nil)
    CodexEval::Run.new(last_message:, events:, workdir:, diff:, error: nil)
  end

  def grade(graders, run, arm: "with", judge: FakeJudge.new([true, true, true]))
    CodexEval::Grader.new(judge:, plugin_name: "ruby-plainspoken").grade(eval_case(graders:), run, arm:)
  end

  def command_event(command, output = "")
    { "type" => "item.completed",
      "item" => { "type" => "command_execution", "command" => command, "aggregated_output" => output } }
  end

  def test_a_regex_grader_reads_the_last_message_by_default
    results = grade([{ "type" => "regex", "name" => "mailer", "pattern" => 'UserMailer\.welcome' }],
                    a_run(last_message: "call UserMailer.welcome(user)"))

    assert results.first["passed"]
  end

  def test_a_not_contains_regex_fails_when_the_pattern_is_present
    grader = { "type" => "regex", "name" => "no-wrapper", "match" => "not_contains", "pattern" => "class UserNotifier" }

    refute grade([grader], a_run(last_message: "class UserNotifier\nend")).first["passed"]
    assert grade([grader], a_run(last_message: "UserMailer.welcome(user)")).first["passed"]
  end

  def test_a_count_regex_needs_exactly_that_many_matches
    grader = { "type" => "regex", "name" => "two", "match" => "count:2", "pattern" => "def " }

    assert grade([grader], a_run(last_message: "def a\ndef b")).first["passed"]
    refute grade([grader], a_run(last_message: "def a")).first["passed"]
  end

  def test_a_trace_regex_reads_command_output
    grader = { "type" => "regex", "name" => "suite", "target" => "trace", "pattern" => "0 failures, 0 errors" }
    run = a_run(events: [command_event("ruby -Itest test/all.rb", "12 runs, 0 failures, 0 errors")])

    assert grade([grader], run).first["passed"]
  end

  def test_a_file_regex_and_file_exists_read_the_work_directory
    Dir.mktmpdir do |workdir|
      FileUtils.mkdir_p(File.join(workdir, "lib"))
      File.write(File.join(workdir, "lib", "booking.rb"), "def hours\nend\n")
      graders = [
        { "type" => "regex", "name" => "in-booking", "target" => { "source" => "file", "path" => "lib/booking.rb" },
          "pattern" => "def hours" },
        { "type" => "file_exists", "name" => "no-helper", "path" => "lib/hours_calculator.rb", "exists" => false },
        { "type" => "file_exists", "name" => "booking-there", "path" => "lib/booking.rb" }
      ]

      results = grade(graders, a_run(workdir:))

      assert(results.all? { |result| result["passed"] }, results.inspect)
    end
  end

  def test_a_file_regex_on_a_missing_file_reads_empty_text
    grader = { "type" => "regex", "name" => "absent", "target" => { "source" => "file", "path" => "nope.rb" },
               "pattern" => "x" }

    Dir.mktmpdir { |workdir| refute grade([grader], a_run(workdir:)).first["passed"] }
  end

  def test_the_skill_counts_as_used_when_codex_reads_its_skill_file
    grader = { "type" => "tool_used", "name" => "skill-fired", "tool" => "Skill",
               "input_match" => "ruby-plainspoken", "min" => 1 }
    read = command_event("cat /tmp/x/plugins/cache/ruby-plainspoken/ruby-plainspoken/0.1.0/skills/ruby-plainspoken/SKILL.md")

    assert grade([grader], a_run(events: [read])).first["passed"]
    refute grade([grader], a_run(events: [command_event("ls")])).first["passed"]
  end

  def test_a_negative_trigger_fails_when_the_skill_was_read
    grader = { "type" => "tool_used", "name" => "skill-silent", "tool" => "Skill",
               "input_match" => "ruby-plainspoken", "max" => 0 }
    read = command_event("cat /x/ruby-plainspoken/SKILL.md")

    refute grade([grader], a_run(events: [read])).first["passed"]
  end

  def test_the_skill_grader_is_not_scored_in_the_without_arm
    grader = { "type" => "tool_used", "name" => "skill-fired", "tool" => "Skill", "min" => 1 }

    result = grade([grader], a_run, arm: "without").first

    refute result["scored"]
    assert result["withOnly"]
  end

  def test_an_llm_grader_passes_on_a_majority_of_votes
    grader = { "type" => "llm", "name" => "judged", "criteria" => "The answer removes the wrapper." }

    assert grade([grader], a_run(last_message: "x"), judge: FakeJudge.new([true, false, true])).first["passed"]
    refute grade([grader], a_run(last_message: "x"), judge: FakeJudge.new([true, false, false])).first["passed"]
  end

  def test_the_judge_sees_the_task_the_answer_and_the_file_changes
    judge = FakeJudge.new([true, true, true])
    grader = { "type" => "llm", "name" => "judged", "criteria" => "Names both callers." }

    grade([grader], a_run(last_message: "the answer", diff: "--- a/lib/booking.rb"), judge:)

    assert_equal({ criteria: "Names both callers.", prompt: "Review this.", answer: "the answer",
                   diff: "--- a/lib/booking.rb" }, judge.calls.first)
  end

  def test_a_run_scores_by_weight_and_passes_only_when_every_scored_grader_passes
    results = [
      { "weight" => 3, "passed" => true, "scored" => true },
      { "weight" => 1, "passed" => false, "scored" => true },
      { "weight" => 5, "passed" => false, "scored" => false }
    ]

    score, passed = CodexEval::Grader.score(results)

    assert_in_delta 0.75, score
    refute passed
  end

  def test_the_codex_command_uses_a_read_only_sandbox_unless_the_case_is_a_fixture
    agent = CodexEval::Agent.new(repo: "/repo", plugin_name: "ruby-plainspoken")

    text = agent.codex_command(eval_case(graders: []), "/work", "/last.txt")
    fixture = agent.codex_command(eval_case(graders: [], kind: "fixture"), "/work", "/last.txt")

    assert_equal %w[-s read-only], text.each_cons(2).find { |flag, _| flag == "-s" }
    assert_equal %w[-s workspace-write], fixture.each_cons(2).find { |flag, _| flag == "-s" }
    assert_equal %w[-C /work], text.each_cons(2).find { |flag, _| flag == "-C" }
    assert_equal "-", text.last, "the prompt goes in on stdin"
  end

  def test_the_two_arms_share_a_private_home_but_use_different_codex_homes
    Dir.mktmpdir do |directory|
      auth = File.join(directory, "auth.json")
      File.write(auth, "{}")
      calls = []
      runner = lambda do |env, command, chdir:, timeout:, stdin: nil|
        calls << [env, command]
        if command.first == "codex" && command[1] == "exec"
          ["{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"done\"}}\n", "", true]
        else
          ["", "", true]
        end
      end
      agent = CodexEval::Agent.new(repo: "/repo", plugin_name: "ruby-plainspoken", runner:, auth_path: auth)

      answers = {}
      agent.open do
        %w[with without].each { |arm| agent.run(eval_case(graders: []), arm) { |run| answers[arm] = run.last_message } }
      end

      execs = calls.select { |_, command| command[1] == "exec" }.map(&:first)
      assert_equal 1, execs.map { |env| env["HOME"] }.uniq.length
      refute_equal Dir.home, execs.first["HOME"], "the user's own skills must not reach either arm"
      assert_equal 2, execs.map { |env| env["CODEX_HOME"] }.uniq.length
      installs = calls.select { |_, command| command[1] == "plugin" }
      assert_equal [execs.first["CODEX_HOME"]], installs.map { |env, _| env["CODEX_HOME"] }.uniq,
                   "only the with arm gets the plugin"
      assert_equal({ "with" => "done", "without" => "done" }, answers)
    end
  end

  def test_a_failed_codex_run_is_reported_as_an_error_not_a_score
    Dir.mktmpdir do |directory|
      auth = File.join(directory, "auth.json")
      File.write(auth, "{}")
      runner = lambda do |_env, command, chdir:, timeout:, stdin: nil|
        command[1] == "exec" ? ["", "timed out after 30s", false] : ["", "", true]
      end
      agent = CodexEval::Agent.new(repo: "/repo", plugin_name: "ruby-plainspoken", runner:, auth_path: auth)

      error = nil
      agent.open { agent.run(eval_case(graders: []), "with") { |run| error = run.error } }

      assert_includes error, "timed out after 30s"
    end
  end

  def test_a_missing_codex_login_stops_before_any_run
    agent = CodexEval::Agent.new(repo: "/repo", plugin_name: "ruby-plainspoken", auth_path: "/nowhere/auth.json")

    error = assert_raises(ArgumentError) { agent.open { flunk "must not run" } }
    assert_includes error.message, "codex login"
  end

  def with_repo(cases)
    Dir.mktmpdir do |repo|
      cases.each do |document|
        directory = File.join(repo, "evals", document["name"])
        FileUtils.mkdir_p(directory)
        File.write(File.join(directory, "case.yaml"), YAML.dump(document))
      end
      yield repo
    end
  end

  def case_yaml(name, tags)
    { "schema_version" => "1.0", "name" => name, "tags" => tags, "runs" => 2,
      "execution" => { "prompt" => "Review this." },
      "graders" => [{ "type" => "regex", "name" => "wanted", "pattern" => "GOOD" }] }
  end

  def options(**overrides)
    Options.new(agents: %w[codex], tags: [], threshold: 0.7, dry_run: false, **overrides)
  end

  def test_the_report_reads_back_through_the_release_gate_with_guards
    cases = [case_yaml("helps", %w[behaviour r2]), case_yaml("guarded", %w[behaviour r3 guard])]
    answers = { %w[helps with] => "GOOD", %w[helps without] => "bad",
                %w[guarded with] => "GOOD", %w[guarded without] => "GOOD" }

    with_repo(cases) do |repo|
      Dir.mktmpdir do |output|
        evaluation = CodexEval::Evaluation.new(options: options, output:, repo:, plugin_name: "ruby-plainspoken",
                                               agent: FakeAgent.new(answers), judge: FakeJudge.new([true]))

        report = evaluation.behaviour_pass

        helps = report.cases.find { |eval_case| eval_case.name == "helps" }
        guarded = report.cases.find { |eval_case| eval_case.name == "guarded" }
        assert_in_delta 1.0, helps.delta
        assert guarded.guard
        assert_empty report.incomplete_reasons
        written = JSON.parse(File.read(File.join(output, "codex-behaviour-report.json")))
        helps_arms = written["cases"].find { |entry| entry["name"] == "helps" }["arms"]
        assert_equal [1, 1], helps_arms["with"].map { |run| run["skillReads"] }
        assert_equal [0, 0], helps_arms["without"].map { |run| run["skillReads"] }

        result = ReleaseResult.decide(trigger: nil, behaviour: nil, codex: nil, threshold: 0.7,
                                      codex_trigger: nil, codex_behaviour: report)
        assert_equal :pass, result.verdict, result.reasons.join("; ")
      end
    end
  end

  def test_a_codex_case_below_the_threshold_blocks_the_release_with_a_codex_reason
    answers = { %w[weak with] => "bad", %w[weak without] => "bad" }

    with_repo([case_yaml("weak", %w[behaviour r2])]) do |repo|
      Dir.mktmpdir do |output|
        report = CodexEval::Evaluation.new(options: options, output:, repo:, plugin_name: "ruby-plainspoken",
                                           agent: FakeAgent.new(answers), judge: FakeJudge.new([true])).behaviour_pass

        result = ReleaseResult.decide(trigger: nil, behaviour: nil, codex: nil, threshold: 0.7, codex_behaviour: report)

        assert_equal :fail, result.verdict
        assert_includes result.reasons.join, "codex: case weak scored 0.00"
      end
    end
  end

  def test_trigger_cases_run_only_the_with_arm
    answers = { %w[trigger-ruby with] => "GOOD" }

    with_repo([case_yaml("trigger-ruby", %w[trigger positive r2]), case_yaml("helps", %w[behaviour r2])]) do |repo|
      Dir.mktmpdir do |output|
        report = CodexEval::Evaluation.new(options: options, output:, repo:, plugin_name: "ruby-plainspoken",
                                           agent: FakeAgent.new(answers), judge: FakeJudge.new([true])).trigger_pass

        assert_equal ["trigger-ruby"], report.cases.map(&:name)
        assert_equal "none", report.ablation
        assert_empty report.incomplete_reasons
      end
    end
  end

  def test_cases_are_picked_by_kind_name_glob_and_every_extra_tag
    cases = [case_yaml("keep-a", %w[behaviour r2 guard]), case_yaml("keep-b", %w[behaviour r2]),
             case_yaml("fix-c", %w[fixture r2 guard]), case_yaml("trigger-d", %w[trigger positive r2])]

    with_repo(cases) do |repo|
      pick = lambda do |**overrides|
        CodexEval::Evaluation.new(options: options(**overrides), output: repo, repo:, plugin_name: "x",
                                  agent: FakeAgent.new({}), judge: FakeJudge.new([true]))
                             .cases(%w[behaviour fixture]).map(&:name)
      end

      assert_equal %w[fix-c keep-a keep-b], pick.call
      assert_equal %w[keep-a keep-b], pick.call(case_glob: "keep-*")
      assert_equal %w[fix-c keep-a], pick.call(tags: %w[guard])
      assert_equal %w[keep-a], pick.call(tags: %w[behaviour guard])
    end
  end
end
