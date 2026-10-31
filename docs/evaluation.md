# Evaluation and release

## Evaluation

`bin/evaluate` decides whether a release may publish. It does not implement its
own evaluator: `claude plugin eval` already runs case files, compares a
with-plugin arm against a no-plugin baseline, and grades against a mixture of
free checks and model-judged criteria, so `bin/evaluate` calls it and applies
the release rule to the result.

```
bin/evaluate --dry-run                 # print the commands and the Codex cases, run nothing
bin/evaluate --agent codex --codex-install-only   # install and skill discovery only, no model calls
bin/evaluate --agent codex             # every case on Codex
bin/evaluate --tag trigger             # the cheap deterministic cases
bin/evaluate                           # everything, both agents
```

It runs two passes over the Claude cases, because they measure different things:

- **Trigger cases** run with no baseline arm. They assert on the Skill tool: the
  three positive cases require the skill to fire, the two negative cases require
  it not to. All graders are free, so this pass costs only the agent runs.
- **Behaviour and fixture cases** run with `--ablation with-without`, so every
  case is also answered without the plugin. A case that scores the same in both
  arms measures nothing about this plugin.
- **Guard cases** carry the `guard` tag. The model already passes them
  without the plugin, so they cannot show a gain. They exist to catch a
  skill edit that makes the agent worse. A guard must still clear the score
  threshold, but the two baseline checks below leave it out.

Then it runs the Codex check: install the plugin into a temporary `CODEX_HOME`
from this repository, and confirm Codex reports it enabled at the right version
with the skill and its reference in the plugin cache.

If that check passes, it runs the same cases on Codex, in the same two passes.
Codex has no `claude plugin eval`, so `bin/codex_eval.rb` does the work:

- Each run is one `codex exec` call. The with arm uses a `CODEX_HOME` with the
  plugin installed. The without arm uses one with only your `auth.json`,
  copied from `~/.codex` and removed after the run.
- Every run gets a temporary `HOME`. Skills in your own `~/.agents` or
  `~/.codex` reach neither arm. That `HOME` has a `.zprofile` that puts the
  Ruby running `bin/evaluate` first on the path, so fixture tests run on it.
- Text cases run in an empty folder with a read-only sandbox. Fixture cases run
  their scaffold in a scratch folder with a workspace-write sandbox.
- "The skill fired" means Codex read the plugin's `SKILL.md`.
- Regex and file graders run locally. LLM graders ask `claude -p --model haiku`
  three times, with no tools, and take the majority. That judge prompt is ours,
  not the one `claude plugin eval` uses, so a Codex score and a Claude score
  compare only roughly.
- `max_turns` is not enforced on Codex; `timeout_seconds` is.
- Each run records `skillReads`, how many times Codex opened the plugin's
  `SKILL.md`. Check it before reading a zero delta: a with arm that never
  opened the skill measured nothing.
- Repeated `--tag` values that are not a kind (`trigger`, `behaviour`,
  `fixture`) must all be on a case for Codex to run it.
- Regex patterns are run by Ruby, where `^` and `$` always match at line
  boundaries.

The Codex reports go through the same release rule, and their reasons start
with `codex:`. Codex does not report a cost, so the summary says "cost not
reported". The judge cost is in the report file as `judgeCostUsd`.

The release result follows one rule, and `bin/evaluate` exits on it:

| Result | Exit | When |
|---|---|---|
| `incomplete` | 2 | Any requested run did not finish. An unfinished run tells you nothing about the score, so this outranks a low score. |
| `fail` | 1 | A case scored below the threshold, a trigger case behaved wrongly in any run, the plugin scored below the no-plugin baseline overall, it made more cases worse than better (both counted over non-guard cases only), or the Codex check failed. The same rules apply to the Codex reports. |
| `pass` | 0 | Everything above is clear. |

### Three things to know before running it

**`claude plugin eval` is in early access**, enabled per organization. Where it
is not enabled it prints "currently in early access" and does nothing;
`bin/evaluate` detects that and tells you so rather than reporting a false
failure. Claude Code documents `CLAUDE_CODE_WALNUT_SPIRE=1` as the enablement
variable for machines that cannot receive the per-organization rollout — set it
in your shell or in `~/.claude/settings.json` under `env`. If you are gated off,
ask your Anthropic contact.

**Each case runs in a sealed sandbox with its own `HOME`**, and Claude Code has
to hand credentials down to it. Where it cannot, every case fails with
`Not logged in · Please run /login` and `bin/evaluate` reports `incomplete`
rather than a score — which is the point of separating the two, but it does mean
a run costing $0.00 and telling you nothing. Log in on the machine, or export
`ANTHROPIC_API_KEY`, before reading anything into a result.

**The full suite costs real money and time.** 34 cases, run on each agent; the trigger cases are
short, the ten fixture cases each get up to 30 turns in a scratch repository,
and the behaviour cases are graded by a model. Use `--tag`, `--case` and
`--max-cost-usd` while working on a rule, and run the whole thing only before a
release. `--max-cost-usd` does not limit Codex, which uses your Codex plan.
`--concurrency N` runs N agent runs at once on both agents.

### The release threshold is not settled yet

`--threshold` defaults to **0.7**, which is a placeholder, not a measured
number. Setting it properly means running the full suite three times, looking at
how much the scores move between identical runs, and choosing a threshold that
sits below the noise. Until that happens, a `pass` from `bin/evaluate` means
"no case failed badly and the plugin beat the baseline", not "this is ready to
publish".

## Coverage

Each case names the requirement it serves in its tags, and
`test/evaluation_catalog_test.rb` fails if any requirement has no case.

| Requirement | Cases |
|---|---|
| Install and update on both agents, with no application gem | `test/install_smoke_test.rb` |
| The skill fires on Ruby and Rails work and not on anything else | `trigger-ruby-refactor`, `trigger-rails-implement`, `trigger-ruby-review`, `trigger-other-language`, `trigger-non-coding` |
| Read the flow before designing | `trace-real-flow`, `follow-service-pattern`, `reject-repeating-defect` |
| Stop at the first thing that already covers the request | `trace-real-flow`, `no-data-on-ruby-3-1`, `rails-facility-over-new-layer` |
| Follow the application's pattern, except when it repeats the defect | `follow-service-pattern`, `reject-repeating-defect` |
| No object without a job; keep the objects that have one | `keep-real-boundary`, `remove-pass-through`, `reject-repeating-defect`, `enumerable-for-repeated-questions`, `plain-object-for-real-responsibility` |
| Inline what a method would only rename; keep a named rule | `inline-obvious-extraction`, `keep-named-domain-rule` |
| No comment that describes readable code; keep a hidden reason | `reject-descriptive-comments`, `keep-hidden-reason-comment` |
| No single-use Sorbet alias, unless it names a domain contract | `inline-one-use-sorbet-alias`, `keep-domain-sorbet-alias` |
| `Data.define` only where it belongs, and only where it exists | `named-value-for-shared-return`, `no-data-on-ruby-3-1`, `no-data-for-entity` |
| Keywords for confusable inputs; positional where required | `keywords-for-confusable-inputs`, `keep-required-positional` |
| Return shapes chosen from what callers need | `keep-local-hash`, `keep-plain-collection`, `named-value-for-shared-return`, `enumerable-for-repeated-questions` |
| Use the Rails facility; a plain object for a real responsibility | `rails-facility-over-new-layer`, `plain-object-for-real-responsibility` |
| Required safety survives a simplification | `keep-required-safety` |
| One focused check, in the framework already there | `follow-service-pattern`, `one-check-in-existing-framework` |
| Split objects by what they know, not by when they run (guards) | `merge-temporal-split`, `keep-knowledge-split` |
| No flag parameter for a decision the method can make; keep a flag that is the contract (guards) | `remove-flag-parameter`, `keep-contract-flag` |
| Let an operation succeed instead of raising; keep the raise when silent success loses data (guards) | `define-error-away`, `keep-raise-on-money` |
| The release gate itself | `test/evaluate_test.rb` |

## Releasing

1. `ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'`
2. `claude plugin validate .` and `claude plugin validate ./skills --strict`
3. Run the full suite three times, settle the threshold, then run once more
   without changing anything
4. `bin/evaluate` must exit 0 with a complete report
5. `claude plugin tag .` — it checks that `plugin.json` and the marketplace
   entry agree before tagging

Bump the version in both `.claude-plugin/plugin.json` and
`.codex-plugin/plugin.json`; `test/plugin_package_test.rb` fails if they
disagree with each other or with the version named in the README.

## Publication handoff for 0.1.0

This is an agent plugin; publication does not involve RubyGems or a gem build.
Keep the version at 0.1.0 until the first release is published.

Local preparation verified on 2026-10-31:

- 85 tests, 1,694 assertions, no failures, errors, or skips, including real
  Claude Code and Codex installation and update checks.
- `claude plugin validate .` and `claude plugin validate ./skills --strict` pass.
- `bin/evaluate --dry-run` enumerates the evaluation commands successfully.

Before publishing:

- Complete the calibration and final evaluation runs described above. Existing
  local single-case reports do not establish a full release pass.
- Create the GitHub repository named in the manifests and configure its Git
  remote. Push `main` only; any local history backup branch is for recovery.
- If submitting to the Claude plugin directory, supply a square PNG or JPEG
  icon before the first submission. The local validator currently warns that
  no icon is present. Validate a clean checkout to avoid ignored macOS files.
- Once the evaluation gate passes, run `claude plugin tag .` and push the
  generated `ruby-plainspoken--v0.1.0` tag alongside `main`.
- Test both GitHub installation commands in the README from fresh agent
  configurations, then update the README's unpublished notice.

Do not treat local installation tests or a dry run as a completed model
evaluation. No release tag is created during preparation.

