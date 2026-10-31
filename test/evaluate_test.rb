# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"

load File.expand_path("../bin/evaluate", __dir__)

class EvaluateTest < Minitest::Test
  def report(cases:, ablation: "with-without", partial: false)
    {
      "schemaVersion" => 1,
      "claudeVersion" => "2.1.263",
      "startedAt" => "2026-09-07T00:00:00.000Z",
      "durationSeconds" => 12,
      "costUsd" => 0.42,
      "partial" => partial,
      "suite" => { "root" => "/repo", "ablation" => ablation, "threshold" => 1, "plugins" => [] },
      "cases" => cases,
      "aggregates" => {
        "casesTotal" => cases.length,
        "casesPassed" => cases.count { |eval_case| eval_case.dig("aggregates", "score").to_f >= 1 },
        "overallScore" => 0,
        "overallPassRate" => 0,
        "meanDelta" => mean_delta(cases)
      }
    }
  end

  def mean_delta(cases)
    deltas = cases.map { |eval_case| eval_case.dig("aggregates", "delta").to_f }
    return 0 if deltas.empty?

    deltas.sum / deltas.length
  end

  def eval_case(name:, score: 1.0, pass_rate: 1.0, score_without: 0.5, delta: nil, runs: 2, errors: [], arms: %w[with without])
    delta ||= score - score_without
    runs_by_arm = arms.to_h do |arm|
      [arm, Array.new(runs) { |index| { "score" => score, "passed" => score >= 1, "error" => errors[index].to_s } }]
    end

    {
      "name" => name,
      "dir" => "evals/#{name}",
      "source" => "case_yaml",
      "promptMarkdown" => "...",
      "runsPerCase" => runs,
      "timeoutSeconds" => 300,
      "maxTurns" => 10,
      "graders" => [],
      "arms" => runs_by_arm,
      "aggregates" => {
        "score" => score, "passRate" => pass_rate,
        "scoreWithout" => score_without, "passRateWithout" => 0.5, "delta" => delta
      }
    }
  end

  def parse(document, guards: [])
    Dir.mktmpdir do |directory|
      path = File.join(directory, "report.json")
      File.write(path, JSON.generate(document))

      ClaudeReport.parse(path, guards:)
    end
  end

  def passing_codex
    CodexResult.new(passed: true, checks: { "skill present in the plugin cache" => true }, failures: [])
  end

  def decide(trigger:, behaviour:, codex: passing_codex, threshold: 0.7)
    ReleaseResult.decide(trigger:, behaviour:, codex:, threshold:)
  end

  def test_a_complete_run_with_every_case_above_the_threshold_passes
    trigger = parse(report(cases: [eval_case(name: "trigger-ruby-refactor", arms: %w[with])], ablation: "none"))
    behaviour = parse(report(cases: [eval_case(name: "remove-pass-through", score: 0.9, score_without: 0.4)]))

    result = decide(trigger:, behaviour:)

    assert_equal :pass, result.verdict
    assert_equal 0, result.exit_code
    assert_empty result.reasons
  end

  def test_a_case_scoring_below_the_threshold_blocks_the_release
    trigger = parse(report(cases: [eval_case(name: "trigger-ruby-refactor", arms: %w[with])], ablation: "none"))
    behaviour = parse(report(cases: [
                               eval_case(name: "keep-required-safety", score: 0.4, score_without: 0.2),
                               eval_case(name: "remove-pass-through", score: 0.95, score_without: 0.4)
                             ]))

    result = decide(trigger:, behaviour:)

    assert_equal :fail, result.verdict
    assert_equal 1, result.exit_code
    assert_equal 1, result.reasons.length
    assert_includes result.reasons.first, "keep-required-safety"
    assert_includes result.reasons.first, "0.40"
  end

  def test_a_run_that_did_not_finish_is_incomplete_rather_than_failed
    behaviour = parse(report(cases: [eval_case(name: "trace-real-flow", errors: ["", "process exited with 1"])]))

    result = decide(trigger: nil, behaviour:)

    assert_equal :incomplete, result.verdict
    assert_equal 2, result.exit_code
    assert_includes result.reasons.join, "did not complete: process exited with 1"
  end

  def test_a_partial_run_is_incomplete
    behaviour = parse(report(cases: [eval_case(name: "trace-real-flow")], partial: true))

    result = decide(trigger: nil, behaviour:)

    assert_equal :incomplete, result.verdict
    assert_includes result.reasons.join, "stopped before every case finished"
  end

  def test_a_missing_run_is_incomplete_even_when_the_scores_look_fine
    document = report(cases: [eval_case(name: "follow-service-pattern")])
    document["cases"][0]["arms"]["with"].pop

    result = decide(trigger: nil, behaviour: parse(document))

    assert_equal :incomplete, result.verdict
    assert_includes result.reasons.join, "completed 3 of 4 requested runs"
  end

  def test_incompleteness_outranks_a_low_score
    behaviour = parse(report(cases: [eval_case(name: "trace-real-flow", score: 0.1, errors: ["", "timed out"])]))

    result = decide(trigger: nil, behaviour:)

    assert_equal :incomplete, result.verdict, "an unfinished run tells us nothing about the score"
  end

  def test_scoring_below_the_no_plugin_baseline_blocks_the_release
    behaviour = parse(report(cases: [
                               eval_case(name: "keep-local-hash", score: 0.8, score_without: 0.95),
                               eval_case(name: "keep-plain-collection", score: 0.8, score_without: 0.9)
                             ]))

    result = decide(trigger: nil, behaviour:)

    assert_equal :fail, result.verdict
    assert_includes result.reasons.join, "below the no-plugin baseline"
  end

  def test_making_more_cases_worse_than_better_blocks_the_release
    behaviour = parse(report(cases: [
                               eval_case(name: "keep-local-hash", score: 0.8, delta: -0.1),
                               eval_case(name: "keep-plain-collection", score: 0.8, delta: -0.1),
                               eval_case(name: "remove-pass-through", score: 0.9, delta: 0.5)
                             ]))

    result = decide(trigger: nil, behaviour:)

    assert_equal :fail, result.verdict
    assert_includes result.reasons.join, "made 2 case(s) worse and only 1 better"
  end

  def test_a_guard_case_below_the_baseline_does_not_block_the_release
    behaviour = parse(report(cases: [
                               eval_case(name: "keep-contract-flag", score: 0.75, delta: -0.25),
                               eval_case(name: "remove-pass-through", score: 1.0, delta: 0.5)
                             ]), guards: ["keep-contract-flag"])

    result = decide(trigger: nil, behaviour:)

    assert_equal :pass, result.verdict, result.reasons.join("; ")
  end

  def test_a_guard_case_below_the_threshold_still_blocks_the_release
    behaviour = parse(report(cases: [eval_case(name: "keep-contract-flag", score: 0.5, delta: 0.0)]),
                      guards: ["keep-contract-flag"])

    result = decide(trigger: nil, behaviour:)

    assert_equal :fail, result.verdict
    assert_includes result.reasons.join, "keep-contract-flag scored 0.50"
  end

  def test_a_run_of_only_guard_cases_skips_the_baseline_checks
    behaviour = parse(report(cases: [
                               eval_case(name: "keep-contract-flag", score: 1.0, delta: -0.25),
                               eval_case(name: "define-error-away", score: 1.0, delta: -0.25)
                             ]), guards: %w[keep-contract-flag define-error-away])

    result = decide(trigger: nil, behaviour:)

    assert_equal :pass, result.verdict, result.reasons.join("; ")
  end

  def test_a_negative_trigger_case_that_activated_the_skill_blocks_the_release
    trigger = parse(report(cases: [
                             eval_case(name: "trigger-ruby-refactor", pass_rate: 1.0, arms: %w[with]),
                             eval_case(name: "trigger-other-language", pass_rate: 0.66, arms: %w[with])
                           ], ablation: "none"))
    behaviour = parse(report(cases: [eval_case(name: "remove-pass-through", score: 0.9)]))

    result = decide(trigger:, behaviour:)

    assert_equal :fail, result.verdict
    assert_includes result.reasons.join, "trigger-other-language"
  end

  def test_a_failed_codex_check_blocks_the_release
    behaviour = parse(report(cases: [eval_case(name: "remove-pass-through", score: 0.9)]))
    codex = CodexResult.new(passed: false, checks: { "plugin enabled" => false },
                            failures: ["codex plugin list does not report the plugin as installed and enabled"])

    result = decide(trigger: nil, behaviour:, codex:)

    assert_equal :fail, result.verdict
    assert_includes result.reasons.join, "codex: codex plugin list does not report"
  end

  def test_every_blocking_reason_is_reported_not_just_the_first
    trigger = parse(report(cases: [eval_case(name: "trigger-non-coding", pass_rate: 0.5, arms: %w[with])], ablation: "none"))
    behaviour = parse(report(cases: [eval_case(name: "keep-required-safety", score: 0.2, score_without: 0.1)]))
    codex = CodexResult.new(passed: false, checks: {}, failures: ["the codex command is not on PATH"])

    result = decide(trigger:, behaviour:, codex:)

    assert_equal 3, result.reasons.length
    assert_includes result.reasons.join, "trigger-non-coding"
    assert_includes result.reasons.join, "keep-required-safety"
    assert_includes result.reasons.join, "not on PATH"
  end

  def test_a_report_schema_the_binary_does_not_produce_is_refused
    document = report(cases: [eval_case(name: "remove-pass-through")])
    document["schemaVersion"] = 2

    error = assert_raises(ArgumentError) { parse(document) }

    assert_includes error.message, "unrecognised report schema version 2"
  end

  def test_the_report_records_the_claude_code_version_it_was_produced_by
    behaviour = parse(report(cases: [eval_case(name: "remove-pass-through")]))

    assert_equal "2.1.263", behaviour.claude_version
  end
def test_an_explicit_runs_override_sets_what_completeness_is_measured_against
  document = report(cases: [eval_case(name: "trigger-ruby-refactor", runs: 3, arms: %w[with])], ablation: "none")
  document["cases"][0]["arms"]["with"] = [{ "score" => 1.0, "passed" => true, "error" => "" }]

  Dir.mktmpdir do |directory|
    path = File.join(directory, "report.json")
    File.write(path, JSON.generate(document))

    overridden = ClaudeReport.parse(path, runs_override: 1)
    assert_empty overridden.incomplete_reasons,
                 "one run was asked for and one arrived, so nothing is missing"

    declared = ClaudeReport.parse(path)
    assert_includes declared.incomplete_reasons.join, "completed 1 of 3 requested runs"
  end
end
end
