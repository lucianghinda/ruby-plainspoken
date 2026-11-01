# Installing Ruby Plainspoken for OpenCode

Ruby Plainspoken supports OpenCode 2.x. OpenCode 1.x is not supported.

## Installation

Add the plugin to your global or project-level `opencode.json`:

```json
{
  "plugins": [
    "ruby-plainspoken@git+https://github.com/lucianghinda/ruby-plainspoken.git"
  ]
}
```

Restart OpenCode. The plugin registers the shared `ruby-plainspoken` skill,
which OpenCode can discover and load with its native `skill` tool. The skill
content is the same one used by Claude Code and Codex.

Before publication, test a local clone by using the absolute file URL of its
entry point in the same `plugins` array:

```json
{
  "plugins": ["file:///absolute/path/to/ruby-plainspoken/.opencode/plugins/ruby-plainspoken.js"]
}
```

This project does not provide a separate OpenCode 1.x install path or bootstrap
script.

## Verification

The repository's OpenCode integration check covers plugin registration. It is
separate from the Claude Code and Codex model evaluations; no live OpenCode
model evaluation is included. See [evaluation and release](../docs/evaluation.md).

