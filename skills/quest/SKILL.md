---
name: quest
description: Create and manage quests — mechanically enforced task gates. Use when starting any task that modifies code, to guarantee completion. Subcommands - create, check, list, done, abandon.
user_invocable: true
---

# Quests

Quests are mechanically enforced task contracts. Each quest defines **gates** that hooks verify. Hooks block `git commit`, `git push`, and `stop` until every gate passes. Quests auto-archive on commit. Quest files are immutable once created.

## CRITICAL: How to write gates

Every gate `check` field MUST be a call to `check-ast`. This is the ONLY allowed gate format:

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast <file> '<tree-sitter-query>' [--min N] [--max N] [--exact N] [--zero]
```

The harness will REJECT any gate that does not contain `check-ast`. The following are ALL FORBIDDEN and will be blocked:
- `grep` — matches text, not code. A comment fools it.
- `test` / `[` — shell conditionals on text output.
- `awk` / `sed` / `rg` — text processing tools.
- `node -e` / `python3 -c` — inline scripts.
- `npm test` / `cargo test` / any test runner.
- Anything that is not `check-ast`.

There are ZERO exceptions. Do not try to work around this.

## How to write a check-ast gate

### Step 1: Run `tree-sitter parse` on the target file

```bash
tree-sitter parse path/to/file.js
```

This outputs the AST as an S-expression. Read it. Find the node types for the code you need to verify.

### Step 2: Write a tree-sitter query that matches the desired structure

Tree-sitter queries use S-expression pattern syntax with `@captures` and `#eq?` predicates.

### Step 3: Use check-ast with that query

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast path/to/file.js '(your_query_here)' --min 1
```

Options:
- `--min N` — at least N matches (default: 1)
- `--max N` — at most N matches
- `--exact N` — exactly N matches
- `--zero` — no matches (same as `--exact 0`)

### Step 4: Test the gate before saving the quest

Run the command. Verify it fails on the current code (before your changes) and would pass on the correct code. Only then save it to the quest file.

## Gate templates

Below are ready-to-use templates. Replace `$FILE`, `$FN_NAME`, `$PARAM_NAME`, etc. with actual values. Always use absolute paths for `$FILE`.

### JS/TS: Function has parameter

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE '(function_declaration name: (identifier) @fn parameters: (formal_parameters (assignment_pattern left: (identifier) @p)) (#eq? @fn "$FN_NAME") (#eq? @p "$PARAM_NAME"))'
```

For required (non-default) params:

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE '(function_declaration name: (identifier) @fn parameters: (formal_parameters (identifier) @p) (#eq? @fn "$FN_NAME") (#eq? @p "$PARAM_NAME"))'
```

### JS/TS: All calls to function have N+ arguments

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE '(call_expression function: (identifier) @fn arguments: (arguments (_) (_)) (#eq? @fn "$FN_NAME"))' --min $CALL_COUNT
```

To verify NO calls have fewer than N args, query for short calls and use `--zero`:

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE '(call_expression function: (identifier) @fn arguments: (arguments (_) .) (#eq? @fn "$FN_NAME"))' --zero
```

### JS/TS: Function exists

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE '(function_declaration name: (identifier) @fn (#eq? @fn "$FN_NAME"))'
```

### JS/TS: No references to old name (rename complete)

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE '((identifier) @id (#eq? @id "$OLD_NAME"))' --zero
```

### Python: Function has parameter

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE '(function_definition name: (identifier) @fn parameters: (parameters (default_parameter name: (identifier) @p)) (#eq? @fn "$FN_NAME") (#eq? @p "$PARAM_NAME"))'
```

### Python: All calls pass keyword argument

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE '(call function: (identifier) @fn arguments: (argument_list (keyword_argument name: (identifier) @kw)) (#eq? @fn "$FN_NAME") (#eq? @kw "$PARAM_NAME"))' --min $CALL_COUNT
```

### Rust: Function has parameter

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE '(function_item name: (identifier) @fn parameters: (parameters (parameter pattern: (identifier) @p)) (#eq? @fn "$FN_NAME") (#eq? @p "$PARAM_NAME"))'
```

### Unknown language or unfamiliar structure

1. Run `tree-sitter parse <file>` — read the full AST
2. Find the nodes you care about
3. Write a query matching that structure
4. Test with `check-ast` before saving

## Subcommands

### `/quest` or `/quest list`

List active quests, run gates, show pass/fail.

### `/quest create`

1. Ask the user what the task is (or infer from context)
2. Run `tree-sitter parse` on the target files to see AST structure
3. Write gates using `check-ast` and the templates above
4. Present quest for user approval
5. Write to `.claude/quests/<name>.json`

### `/quest check`

Re-run all gates with verbose failure output.

### `/quest done <name>`

Run all gates. If ALL pass, archive to `.claude/quests/done/`. Refuse if any fail.

### `/quest abandon <name>`

Delete the quest file. For when the task changes or gates are wrong.

## Complete example

Task: "Add a `language` parameter to `greet()` in `app.js`, update both call sites"

First, run `tree-sitter parse app.js` to see the AST. Then write the quest:

```json
{
  "name": "add-language-param",
  "description": "Add language param to greet(), update both call sites",
  "created": "2026-03-25T00:00:00Z",
  "gates": [
    {
      "name": "greet() has language param",
      "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /absolute/path/to/app.js '(function_declaration name: (identifier) @fn parameters: (formal_parameters (assignment_pattern left: (identifier) @p)) (#eq? @fn \"greet\") (#eq? @p \"language\"))'"
    },
    {
      "name": "both call sites pass 2 arguments",
      "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /absolute/path/to/app.js '(call_expression function: (identifier) @fn arguments: (arguments (_) (_)) (#eq? @fn \"greet\"))' --min 2"
    },
    {
      "name": "no single-arg calls to greet remain",
      "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /absolute/path/to/app.js '(call_expression function: (identifier) @fn arguments: (arguments (_) .) (#eq? @fn \"greet\"))' --zero"
    }
  ]
}
```

## Quest file format

```json
{
  "name": "descriptive-kebab-name",
  "description": "One-line description",
  "created": "ISO-8601",
  "gates": [
    {
      "name": "human-readable gate description",
      "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast <file> '<tree-sitter-query>' [options]"
    }
  ]
}
```

Quest files are immutable after creation. To change gates, `/quest abandon` and recreate.

## Lifecycle

1. Plan approved → hook fires → marker set
2. Gates defined with `check-ast` → marker cleared → edits unblocked
3. Work proceeds
4. `git commit` → all gates verified → auto-archived to `.claude/quests/done/`
