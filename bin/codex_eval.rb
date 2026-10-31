# frozen_string_literal: true

# Runs the eval cases against Codex with `codex exec`, and writes the same
# report shape as `claude plugin eval --json`, so ClaudeReport and
# ReleaseResult read it unchanged.
#
# Isolation: every run gets a temporary HOME, so skills in ~/.agents or
# ~/.codex never reach either arm. The "with" arm uses a CODEX_HOME that has
# the plugin installed; the "without" arm uses one that has only auth.json.
# The judge is `claude -p` with no tools. Its prompt is written here, not taken
# from `claude plugin eval`, so Codex and Claude scores compare only roughly.

require "json"
require "yaml"
require "open3"
require "fileutils"
require "tmpdir"
require "rbconfig"
require "time"

module CodexEval
  KIND_TAGS = %w[trigger behaviour fixture].freeze
  DEFAULT_TIMEOUT = 300
  JUDGE_VOTES = 3
  DEFAULT_JUDGE_MODEL = "haiku"
  MAX_DIFF_CHARS = 20_000

  EvalCase = Data.define(:name, :tags, :prompt, :runs, :timeout, :scaffold, :graders) do
    def self.load(path)
      document = YAML.safe_load(File.read(path))
      scaffold = document.dig("context", "scaffold_script")

      new(
        name: document.fetch("name"),
        tags: document.fetch("tags", []),
        prompt: document.dig("execution", "prompt").to_s,
        runs: document.fetch("runs", 1),
        timeout: document.dig("execution", "timeout_seconds") || DEFAULT_TIMEOUT,
        scaffold: scaffold && File.expand_path(scaffold, File.dirname(path)),
        graders: document.fetch("graders", [])
      )
    end

    def kind = (tags & KIND_TAGS).first
    def fixture? = kind == "fixture"
  end

  # What one Codex run left behind. `workdir` is gone after the run is graded.
  Run = Data.define(:last_message, :events, :workdir, :diff, :error) do
    def trace
      events.filter_map do |event|
        item = event["item"] || {}
        case item["type"]
        when "agent_message", "reasoning" then item["text"]
        when "command_execution" then [item["command"], item["aggregated_output"]].compact.join("\n")
        when "file_change" then Array(item["changes"]).map { |change| change["path"] }.join("\n")
        end
      end.join("\n")
    end

    def commands
      events.filter_map { |event| event.dig("item", "command") if event.dig("item", "type") == "command_execution" }.uniq
    end

    def skill_reads(match)
      commands.count { |command| command.include?("SKILL.md") && command.include?(match) }
    end
  end

  # Grades one run. Returns grader results in the shape claude plugin eval uses.
  class Grader
    def initialize(judge:, plugin_name:)
      @judge = judge
      @plugin_name = plugin_name
    end

    def grade(eval_case, run, arm:)
      eval_case.graders.map { |grader| grade_one(grader, eval_case, run, arm) }
    end

    def self.score(results)
      scored = results.select { |result| result["scored"] }
      total = scored.sum { |result| result["weight"] }
      return [0.0, false] if total.zero?

      earned = scored.select { |result| result["passed"] }.sum { |result| result["weight"] }
      [earned / total.to_f, scored.all? { |result| result["passed"] }]
    end

    private

    def grade_one(grader, eval_case, run, arm)
      with_only = grader["type"] == "tool_used"
      base = { "name" => grader["name"], "weight" => grader.fetch("weight", 1), "withOnly" => with_only,
               "scored" => !(with_only && arm == "without") }

      passed, explanation, extra = case grader["type"]
                                   when "regex" then regex(grader, run)
                                   when "file_exists" then file_exists(grader, run)
                                   when "tool_used" then tool_used(grader, run)
                                   when "llm" then llm(grader, eval_case, run)
                                   else [false, "grader type #{grader['type']} is not supported on codex", {}]
                                   end

      base.merge("passed" => passed, "explanation" => explanation).merge(extra || {})
    end

    def regex(grader, run)
      text = regex_target(grader["target"], run)
      count = text.scan(Regexp.new(grader.fetch("pattern"))).length
      mode = grader["match"] || "contains"

      passed = case mode
               when "contains" then count.positive?
               when "not_contains" then count.zero?
               when /\Acount:(\d+)\z/ then count == Regexp.last_match(1).to_i
               else false
               end
      [passed, "#{count} match(es), mode #{mode}"]
    end

    def regex_target(target, run)
      case target
      when nil, "last_message" then run.last_message.to_s
      when "trace" then run.trace
      when Hash
        path = File.join(run.workdir.to_s, target.fetch("path"))
        File.file?(path) ? File.read(path) : ""
      else ""
      end
    end

    def file_exists(grader, run)
      present = File.exist?(File.join(run.workdir.to_s, grader.fetch("path")))
      wanted = grader.fetch("exists", true)
      [present == wanted, present ? "file present" : "file absent"]
    end

    def tool_used(grader, run)
      return [false, "only the Skill tool can be checked on codex", {}] unless grader["tool"] == "Skill"

      reads = run.skill_reads(grader["input_match"] || @plugin_name)
      passed = reads >= grader.fetch("min", 0) && (grader["max"].nil? || reads <= grader["max"])
      [passed, "skill file read #{reads} time(s)"]
    end

    def llm(grader, eval_case, run)
      votes = @judge.votes(criteria: grader.fetch("criteria"), prompt: eval_case.prompt,
                           answer: run.last_message.to_s, diff: run.diff)
      passed = votes.count(true) * 2 > votes.length
      [passed, "judge votes: #{votes.map { |vote| vote ? 'PASS' : 'FAIL' }.join(' ')}",
       { "judgeVotes" => votes, "evidence" => run.last_message.to_s }]
    end
  end

  # Asks `claude -p` for PASS or FAIL, several times, with no tools.
  class Judge
    attr_reader :cost_usd

    def initialize(model: nil, votes: JUDGE_VOTES, command: nil)
      @model = model || DEFAULT_JUDGE_MODEL
      @votes = votes
      @command = command || method(:claude)
      @cost_usd = 0.0
      @lock = Mutex.new
    end

    def votes(criteria:, prompt:, answer:, diff: nil)
      text = judge_prompt(criteria:, prompt:, answer:, diff:)
      Array.new(@votes) do
        verdict, cost = @command.call(text, @model)
        @lock.synchronize { @cost_usd += cost.to_f }
        verdict.to_s.strip.upcase.start_with?("PASS")
      end
    end

    private

    def judge_prompt(criteria:, prompt:, answer:, diff:)
      changes = diff.to_s.empty? ? "" : "<changes>\n#{diff[0, MAX_DIFF_CHARS]}\n</changes>\n\n"

      <<~PROMPT
        You grade one answer from a coding agent against one criterion.

        <task>
        #{prompt}
        </task>

        <answer>
        #{answer}
        </answer>

        #{changes}<criterion>
        #{criteria}
        </criterion>

        Decide if the answer, and the file changes if any are shown, meet the
        criterion. Reply with exactly one word: PASS or FAIL.
      PROMPT
    end

    def claude(text, model)
      Dir.mktmpdir("codex-judge") do |directory|
        output, _error, status = Open3.capture3(
          "claude", "-p", "--model", model, "--tools", "", "--no-session-persistence",
          "--output-format", "json", stdin_data: text, chdir: directory
        )
        return ["FAIL", 0] unless status.success?

        document = JSON.parse(output)
        document = document.find { |entry| entry["type"] == "result" } if document.is_a?(Array)
        [document["result"], document["total_cost_usd"]]
      end
    rescue JSON::ParserError
      ["FAIL", 0]
    end
  end

  # Builds the isolated homes and runs one case once in one arm.
  class Agent
    ARMS = %w[with without].freeze

    def initialize(repo:, plugin_name:, model: nil, runner: nil, auth_path: nil)
      @repo = repo
      @plugin_name = plugin_name
      @model = model
      @runner = runner || method(:run_command)
      @auth_path = auth_path || File.join(ENV.fetch("CODEX_HOME", File.join(Dir.home, ".codex")), "auth.json")
    end

    # Yields self with the homes set up, and removes them afterwards.
    def open
      Dir.mktmpdir("codex-eval") do |root|
        @root = root
        @user_home = File.join(root, "home")
        @codex_homes = ARMS.to_h { |arm| [arm, File.join(root, "codex-#{arm}")] }
        prepare_homes
        yield self
      end
    end

    def run(eval_case, arm)
      Dir.mktmpdir("case", @root) do |case_root|
        workdir = File.join(case_root, "work")
        baseline = File.join(case_root, "baseline")
        FileUtils.mkdir_p(workdir)

        if eval_case.scaffold
          _, error, ok = @runner.call({}, ["bash", eval_case.scaffold], chdir: workdir, timeout: 120)
          return yield Run.new(last_message: "", events: [], workdir:, diff: nil, error: "scaffold failed: #{error}") unless ok

          FileUtils.cp_r(workdir, baseline)
        end

        last_path = File.join(case_root, "last-message.txt")
        output, error, ok = @runner.call(codex_env(arm), codex_command(eval_case, workdir, last_path),
                                         chdir: workdir, timeout: eval_case.timeout, stdin: eval_case.prompt)
        events = parse_events(output)
        last = File.file?(last_path) ? File.read(last_path) : last_agent_message(events)
        diff = eval_case.scaffold ? diff_of(baseline, workdir) : nil
        failure = ok ? nil : "codex exec failed: #{error.to_s.lines.last(3).join.strip}"

        yield Run.new(last_message: last, events:, workdir:, diff:, error: failure)
      end
    end

    def codex_command(eval_case, workdir, last_path)
      sandbox = eval_case.fixture? ? "workspace-write" : "read-only"
      command = ["codex", "exec", "--json", "--ephemeral", "--skip-git-repo-check",
                 "-s", sandbox, "-C", workdir, "-o", last_path]
      command.push("-m", @model) if @model
      command.push("-")
    end

    def codex_env(arm)
      { "HOME" => @user_home, "CODEX_HOME" => @codex_homes.fetch(arm) }
    end

    private

    def prepare_homes
      raise ArgumentError, "no Codex login found at #{@auth_path}; run `codex login` first" unless File.file?(@auth_path)

      FileUtils.mkdir_p(@user_home)
      ruby_path = "export PATH=\"#{RbConfig::CONFIG['bindir']}:$PATH\"\n"
      %w[.zprofile .bash_profile].each { |name| File.write(File.join(@user_home, name), ruby_path) }

      @codex_homes.each_value do |home|
        FileUtils.mkdir_p(home)
        FileUtils.cp(@auth_path, File.join(home, "auth.json"))
      end

      env = codex_env("with")
      [["plugin", "marketplace", "add", @repo], ["plugin", "add", "#{@plugin_name}@#{@plugin_name}"]].each do |arguments|
        _, error, ok = @runner.call(env, ["codex", *arguments], chdir: @root, timeout: 120)
        raise "codex #{arguments.first(3).join(' ')} failed: #{error}" unless ok
      end
    end

    def parse_events(output)
      output.to_s.each_line.filter_map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    def last_agent_message(events)
      events.reverse.find { |event| event.dig("item", "type") == "agent_message" }&.dig("item", "text").to_s
    end

    def diff_of(before, after)
      output, = @runner.call({}, ["diff", "-ruN", before, after], chdir: @root, timeout: 60)
      output.to_s.gsub("#{before}/", "a/").gsub("#{after}/", "b/")
    end

    def run_command(env, command, chdir:, timeout:, stdin: nil)
      Open3.popen3(env, *command, chdir:, pgroup: true) do |input, out, err, waiter|
        input.write(stdin) if stdin
        input.close
        readers = [out, err].map { |stream| Thread.new { stream.read } }

        unless waiter.join(timeout)
          Process.kill("TERM", -waiter.pid)
          waiter.join(5) || Process.kill("KILL", -waiter.pid)
          return [readers[0].value, "timed out after #{timeout}s", false]
        end

        [readers[0].value, readers[1].value, waiter.value.success?]
      end
    rescue Errno::ENOENT => e
      ["", e.message, false]
    end
  end

  # Picks the cases, runs both arms, and writes a claude-plugin-eval shaped report.
  class Evaluation
    def initialize(options:, output:, repo:, plugin_name:, agent: nil, judge: nil)
      @options = options
      @output = output
      @repo = repo
      @plugin_name = plugin_name
      @kinds = options.tags & KIND_TAGS
      @extra_tags = options.tags - KIND_TAGS
      @judge = judge || Judge.new(model: options.judge_model)
      @agent = agent || Agent.new(repo:, plugin_name:, model: options.codex_model)
    end

    def trigger_pass
      run_pass(label: "codex-trigger", kinds: %w[trigger], arms: %w[with])
    end

    def behaviour_pass
      run_pass(label: "codex-behaviour", kinds: %w[behaviour fixture], arms: %w[with without])
    end

    def cases(kinds)
      wanted = @kinds.empty? ? kinds : @kinds & kinds
      Dir.glob(File.join(@repo, "evals", "*", "case.yaml")).sort.map { |path| EvalCase.load(path) }.select do |eval_case|
        wanted.include?(eval_case.kind) &&
          (@options.case_glob.nil? || File.fnmatch(@options.case_glob, eval_case.name)) &&
          (@extra_tags - eval_case.tags).empty?
      end
    end

    private

    def run_pass(label:, kinds:, arms:)
      selected = cases(kinds)
      return nil if selected.empty?

      if @options.dry_run
        selected.each do |eval_case|
          warn "would run on codex (#{arms.join(' and ')}, #{runs_for(eval_case)} run(s)): #{eval_case.name}"
        end
        return nil
      end

      warn "running on codex: #{selected.length} #{kinds.join('/')} case(s), arms #{arms.join(' and ')}"
      document = @agent.open { evaluate(selected, arms) }
      document["suite"]["ablation"] = arms.length == 2 ? "with-without" : "none"

      path = File.join(@output, "#{label}-report.json")
      File.write(path, "#{JSON.pretty_generate(document)}\n")
      ClaudeReport.parse(path, runs_override: @options.runs, guards: guard_case_names(@repo))
    end

    def evaluate(selected, arms)
      grader = Grader.new(judge: @judge, plugin_name: @plugin_name)
      jobs = selected.flat_map do |eval_case|
        arms.flat_map { |arm| Array.new(runs_for(eval_case)) { |index| [eval_case, arm, index] } }
      end
      results = run_jobs(jobs) { |eval_case, arm, _index| run_and_grade(grader, eval_case, arm) }

      cases = selected.map do |eval_case|
        by_arm = arms.to_h do |arm|
          [arm, jobs.each_index.select { |i| jobs[i][0] == eval_case && jobs[i][1] == arm }.map { |i| results[i] }]
        end
        case_document(eval_case, by_arm)
      end

      report_document(cases)
    end

    def run_and_grade(grader, eval_case, arm)
      started = Time.now
      @agent.run(eval_case, arm) do |run|
        next run_document(score: 0, passed: false, error: run.error, graders: [], started:) if run.error

        results = grader.grade(eval_case, run, arm:)
        score, passed = Grader.score(results)
        run_document(score:, passed:, error: nil, graders: results, started:,
                     tokens: run.events.find { |event| event["type"] == "turn.completed" }&.dig("usage"),
                     skill_reads: run.skill_reads(@plugin_name))
      end
    end

    def run_jobs(jobs, &block)
      results = Array.new(jobs.length)
      queue = Queue.new
      jobs.each_with_index { |job, index| queue << [job, index] }
      workers = Array.new([@options.concurrency || 1, 1].max) do
        Thread.new do
          loop do
            job, index = queue.pop(true)
            results[index] = block.call(*job)
          rescue ThreadError
            break
          end
        end
      end
      workers.each(&:join)
      results
    end

    def runs_for(eval_case) = @options.runs || eval_case.runs

    # skillReads shows whether the with arm opened the skill at all; a zero
    # delta means little when it did not.
    def run_document(score:, passed:, error:, graders:, started:, tokens: nil, skill_reads: nil)
      { "score" => score, "passed" => passed, "error" => error, "graders" => graders,
        "startedAt" => started.utc.iso8601, "durationSeconds" => (Time.now - started).round, "tokens" => tokens,
        "skillReads" => skill_reads }
    end

    def case_document(eval_case, by_arm)
      with = by_arm.fetch("with")
      without = by_arm["without"]
      score = mean(with.map { |run| run["score"] })
      score_without = without && mean(without.map { |run| run["score"] })

      {
        "name" => eval_case.name, "tags" => eval_case.tags, "runsPerCase" => runs_for(eval_case),
        "arms" => by_arm,
        "aggregates" => {
          "score" => score, "passRate" => mean(with.map { |run| run["passed"] ? 1 : 0 }),
          "scoreWithout" => score_without,
          "passRateWithout" => without && mean(without.map { |run| run["passed"] ? 1 : 0 }),
          "delta" => score_without ? score - score_without : 0
        }
      }
    end

    def report_document(cases)
      version = begin
        Open3.capture2("codex", "--version").first
      rescue Errno::ENOENT
        nil
      end
      {
        "schemaVersion" => 1, "agent" => "codex", "codexVersion" => version.to_s.strip,
        "claudeVersion" => nil, "costUsd" => nil, "judgeCostUsd" => @judge.cost_usd.round(4),
        "partial" => false, "suite" => { "root" => @repo }, "cases" => cases,
        "aggregates" => { "casesTotal" => cases.length, "meanDelta" => mean(cases.map { |c| c.dig("aggregates", "delta") }) }
      }
    end

    def mean(values)
      return 0 if values.empty?

      values.sum / values.length.to_f
    end
  end
end
