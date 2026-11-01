# Ruby Plainspoken

When you ask a coding agent to change a Ruby or Rails application, it can add
layers that make the code harder to follow: a service object for one call, a
wrapper around a Rails feature, or a method that only renames an expression.

Ruby Plainspoken is a plugin for Claude Code, Codex, and OpenCode 2.x that helps
your agent make the smallest change that fits your application. It reads the
existing code and tests first, then looks for a solution in your application,
Ruby, Rails, or the gems you already use.

The goal is fewer concepts, not fewer objects. An object that owns a real
responsibility or boundary has a place. Simplicity should also preserve your
validation, authorization, database integrity, error handling, and tests.

**Version 0.1.0 is not published yet.** Until it is, install from a local clone.

## Install

### Claude Code

```sh
claude plugin marketplace add /path/to/ruby-plainspoken
claude plugin install ruby-plainspoken@ruby-plainspoken
```

### Codex

```sh
codex plugin marketplace add /path/to/ruby-plainspoken
codex plugin add ruby-plainspoken@ruby-plainspoken
```

### OpenCode 2.x

Add the GitHub plugin entry to your OpenCode configuration (`opencode.json`):

```json
{
  "plugins": [
    "ruby-plainspoken@git+https://github.com/lucianghinda/ruby-plainspoken.git"
  ]
}
```

Restart OpenCode. The plugin registers the shared `ruby-plainspoken` skill.
This integration supports OpenCode 2.x only; see the
[OpenCode install notes](.opencode/INSTALL.md).

After publication, you can add the marketplace from
`lucianghinda/ruby-plainspoken` in Claude Code or
`https://github.com/lucianghinda/ruby-plainspoken.git` in Codex.

```sh
claude plugin marketplace add lucianghinda/ruby-plainspoken
claude plugin install ruby-plainspoken@ruby-plainspoken

codex plugin marketplace add https://github.com/lucianghinda/ruby-plainspoken.git
codex plugin add ruby-plainspoken@ruby-plainspoken
```

The plugin lives at the repository root. Claude's marketplace source is `./`;
Codex's source is `./plugins/ruby-plainspoken`, a symlink to that same root.
The shared skill is `skills/ruby-plainspoken/SKILL.md`, and the Codex plugin
manifest loads it through `"skills": "./skills/"`. These paths are relative to
the cloned repository, so they do not need the GitHub URL prepended.

All three agents use the same [skill](skills/ruby-plainspoken/SKILL.md). It loads
automatically for Ruby and Rails work; in Claude Code, you can also invoke it
with `/ruby-plainspoken:ruby-plainspoken`. You do not need to add a gem to your
application.

## What the skill does

- Traces the relevant code and reads the tests before choosing a design.
- Uses existing application patterns and Rails features when they fit.
- Keeps names and objects that explain a domain rule or own a responsibility.
- Avoids layers, comments, and abstractions that only repeat what the code says.
- Preserves required safety checks and adds a focused test using the project's
  existing test framework.

Your instructions and the repository's instructions take precedence over the
skill. It complements your tests, linters, security tools, and code review.
See the [reference](skills/ruby-plainspoken/references/ruby-and-rails.md) for
examples and exceptions.

## Development

Ruby 3.2 or newer is required. Ruby tests use the standard library and do
not need Bundler. The OpenCode registration test also requires Node.js to
load the JavaScript plugin; no npm dependencies are needed.

Run the tests:

```sh
ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
```

The installation smoke tests use the real `claude` and `codex` commands when
available, with temporary configuration directories.

To check the evaluation commands without running model calls:

```sh
bin/evaluate --dry-run
```

The full evaluation compares agent runs with and without the plugin. It takes
time and costs money, and its release threshold still needs calibration. See
[evaluation and release](docs/evaluation.md) for the commands, limitations, and
release checklist.

## License

[MIT](LICENSE).
