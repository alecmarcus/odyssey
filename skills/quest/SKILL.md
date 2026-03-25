---
name: quest
description: Create and manage quests — mechanically enforced task gates. Use when starting any task that modifies code, to guarantee completion. Subcommands - create, check, list, done, abandon.
user_invocable: true
---

# Quests

Quests are mechanically enforced task contracts. Each quest defines **gates** — shell commands that must exit 0. Hooks block `git commit`, `git push`, and `stop` until every active gate passes. Quests auto-archive when all gates pass on commit.

Quest files live at `.claude/quests/<name>.json` in the project directory.

## Subcommands

### `/quest` or `/quest list`
List active quests, run gates, show status:
```
Quest: <name> — <description>
  ✓ gate name
  ✗ gate name
    check: <the failing command>
```

### `/quest create`
1. Ask the user what the task is (or infer from context)
2. Parse intent into a gate template (see below)
3. Generate gates using tree-sitter queries via `check-ast`
4. Present quest for user approval
5. Write to `.claude/quests/<name>.json`

### `/quest check`
Re-run all gates with verbose failure output.

### `/quest done <name>`
Run all gates. If ALL pass, archive to `.claude/quests/done/`. Refuse if any fail.

### `/quest abandon <name>`
Delete the quest file. For when the task changes or gates are wrong.

## Gate Checker: `check-ast`

All structural gates MUST use `check-ast` — the tree-sitter query wrapper bundled with odyssey. Located at `${CLAUDE_PLUGIN_ROOT}/bin/check-ast`.

**NO GREP.** Grep matches text, not code. Comments and strings fool it. `check-ast` operates on the parsed AST — cheat-proof by construction.

### Usage

```bash
check-ast <file> '<tree-sitter-query>' [--min N] [--max N] [--exact N] [--zero]
check-ast <file> <query-file.scm> [--min N] [--max N] [--exact N] [--zero]
```

Options:
- `--min N` — at least N matches (default: 1)
- `--max N` — at most N matches
- `--exact N` — exactly N matches
- `--zero` — no matches (shorthand for `--exact 0`)

### Referencing check-ast in gates

In quest gate `check` fields, use the full path to the bundled binary:

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast <file> '<query>' [options]
```

The hook runner expands `${CLAUDE_PLUGIN_ROOT}` automatically when running from a plugin context. For gates run via bash directly, use the resolved path.

## Gate Templates — Tree-sitter Queries

Match the task to a template. Fill in the blanks. To figure out the right query structure, run `tree-sitter parse <file>` first to see the AST node types for the target language.

### JS/TS: Function has parameter

```bash
check-ast $FILE '(function_declaration
  name: (identifier) @fn
  parameters: (formal_parameters
    (assignment_pattern left: (identifier) @p))
  (#eq? @fn "$FN_NAME")
  (#eq? @p "$PARAM_NAME"))'
```

For required (non-default) params:
```bash
check-ast $FILE '(function_declaration
  name: (identifier) @fn
  parameters: (formal_parameters (identifier) @p)
  (#eq? @fn "$FN_NAME")
  (#eq? @p "$PARAM_NAME"))'
```

### JS/TS: All calls have N+ arguments

```bash
# Calls with 2 args (use N (_) nodes for N args)
check-ast $FILE '(call_expression
  function: (identifier) @fn
  arguments: (arguments (_) (_))
  (#eq? @fn "$FN_NAME"))' --min $CALL_COUNT
```

To verify NO calls have fewer than N args, query for calls with <N args and use `--zero`:
```bash
# No 1-arg calls remain
check-ast $FILE '(call_expression
  function: (identifier) @fn
  arguments: (arguments (_) .)
  (#eq? @fn "$FN_NAME"))' --zero
```

### JS/TS: Function exists

```bash
check-ast $FILE '(function_declaration
  name: (identifier) @fn
  (#eq? @fn "$FN_NAME"))'
```

### JS/TS: No references to old name (rename complete)

```bash
check-ast $FILE '((identifier) @id (#eq? @id "$OLD_NAME"))' --zero
```

### Python: Function has parameter

```bash
check-ast $FILE '(function_definition
  name: (identifier) @fn
  parameters: (parameters
    (default_parameter name: (identifier) @p))
  (#eq? @fn "$FN_NAME")
  (#eq? @p "$PARAM_NAME"))'
```

### Python: All calls have N+ arguments

```bash
check-ast $FILE '(call
  function: (identifier) @fn
  arguments: (argument_list (keyword_argument name: (identifier) @kw))
  (#eq? @fn "$FN_NAME")
  (#eq? @kw "$PARAM_NAME"))' --min $CALL_COUNT
```

### Rust: Function has parameter

```bash
check-ast $FILE '(function_item
  name: (identifier) @fn
  parameters: (parameters (parameter pattern: (identifier) @p))
  (#eq? @fn "$FN_NAME")
  (#eq? @p "$PARAM_NAME"))'
```

### Any language: File runs without error

```bash
cd $PROJECT && $RUN_CMD
```

This is the one gate that doesn't need tree-sitter — runtime execution is its own verification.

## Discovering Query Patterns

When writing gates for a new language or unfamiliar AST structure:

1. Run `tree-sitter parse <file>` to see the full S-expression AST
2. Find the nodes you care about
3. Write a query that matches that structure
4. Test with `check-ast <file> '<query>'` before saving the quest

## Quest File Format

```json
{
  "name": "descriptive-kebab-name",
  "description": "One-line description",
  "created": "ISO-8601",
  "gates": [
    {
      "name": "human-readable gate description",
      "check": "shell command that exits 0 on success"
    }
  ]
}
```

## Lifecycle

1. Plan approved → `plan-to-quest` hook fires → marker set
2. Quest gates defined → marker cleared → edits unblocked
3. Work proceeds
4. `git commit` → all gates verified → **auto-archived** to `.claude/quests/done/`
5. Quest cleanup is automatic. No manual `/quest done` needed.
