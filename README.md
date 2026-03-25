# Odyssey

Mechanically enforced task gates for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Quests define acceptance criteria as tree-sitter AST queries — hooks block `git commit`, `git push`, and `stop` until all gates pass.

Gates operate on the parsed AST, not text. Comments and strings are invisible. Can't be cheated.

## Prerequisites

### tree-sitter CLI

```bash
cargo install tree-sitter-cli
```

### Grammars

```bash
tree-sitter init-config

mkdir -p ~/.config/tree-sitter/grammars && cd ~/.config/tree-sitter/grammars
git clone --depth 1 https://github.com/tree-sitter/tree-sitter-javascript.git
git clone --depth 1 https://github.com/tree-sitter/tree-sitter-python.git
git clone --depth 1 https://github.com/tree-sitter/tree-sitter-typescript.git
git clone --depth 1 https://github.com/tree-sitter/tree-sitter-rust.git
```

Add the grammars directory to `~/.config/tree-sitter/config.json`:

```json
{
  "parser-directories": [
    "/Users/YOU/.config/tree-sitter/grammars"
  ]
}
```

Verify: `tree-sitter parse <any-source-file>` should output an S-expression AST.

## Install

```
/plugin marketplace add alecmarcus/claude-plugins
/plugin install odyssey@alecmarcus
```

## How it works

1. **Plan** → ExitPlanMode hook fires, sets `.plan-pending` marker
2. **Define gates** → Claude creates quest with tree-sitter gates, marker clears, edits unblocked
3. **Work** → Claude implements the task
4. **Commit** → hook runs all gates. Fails → blocked. Passes → committed, quest auto-archived
5. **Stop** → hook blocks if any gates still failing

### Hooks

| Event | Hook | Behavior |
|-------|------|----------|
| PreToolUse `Bash` | `enforce-quests.sh` | Blocks `git commit`/`push` if gates fail |
| PreToolUse `Edit`/`Write` | `require-quest.sh` | Blocks code edits if plan approved but no quest defined |
| PostToolUse `ExitPlanMode` | `plan-to-quest.sh` | Sets marker, injects gate-creation instruction |
| Stop | `stop-guard.sh` | Blocks stop if gates fail |

## Usage

### Create a quest

```
/quest create
```

Or quests are created automatically when exiting plan mode.

### Check gate status

```
/quest check
```

### Abandon a quest

```
/quest abandon <name>
```

## Writing gates

Gates use `check-ast` — a tree-sitter query wrapper bundled with the plugin.

```bash
check-ast <file> '<tree-sitter-query>' [--min N] [--max N] [--exact N] [--zero]
```

### Examples

Function has parameter:
```bash
check-ast app.js '(function_declaration
  name: (identifier) @fn
  parameters: (formal_parameters
    (assignment_pattern left: (identifier) @p))
  (#eq? @fn "greet")
  (#eq? @p "language"))'
```

All calls have 2+ arguments:
```bash
check-ast app.js '(call_expression
  function: (identifier) @fn
  arguments: (arguments (_) (_))
  (#eq? @fn "greet"))' --min 2
```

Old name fully removed:
```bash
check-ast app.js '((identifier) @id (#eq? @id "oldName"))' --zero
```

To discover the right query structure for any file, run `tree-sitter parse <file>` and inspect the AST node types.

## License

MIT
