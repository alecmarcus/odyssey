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

## High-level checks (PREFERRED)

Use `--check` mode. It generates the right tree-sitter queries automatically. Supports JS/TS, Python, Rust.

### fn-params — verify function signature with optional defaults

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE --check fn-params $FN_NAME param1 param2="defaultValue" param3
```

Verifies each parameter exists in the function signature, in order. For defaults, checks the value matches.

### call-min-args — all calls have at least N arguments

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE --check call-min-args $FN_NAME $N
```

Counts total calls vs calls with N+ args. Fails if any call has fewer.

### call-arg-matches — specific argument matches a regex

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE --check call-arg-matches $FN_NAME $ARG_POS $REGEX
```

Verifies EVERY call to the function has an argument at position N matching the regex. Fails if any call is missing it or doesn't match.

### symbol-used — declared AND referenced (not dead code)

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE --check symbol-used $NAME
```

Verifies the identifier appears at least twice in the AST — once for declaration, once for use. Catches "imported but never called" cheats.

### import-used — imported AND actually referenced

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE --check import-used $NAME
```

Verifies the symbol appears in an import statement AND is referenced elsewhere in the code.

### assigned — variable assigned from matching expression

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE --check assigned $VAR_NAME $VALUE_REGEX
```

Verifies the variable is assigned from an expression matching the regex. Catches "declared but assigned to wrong thing".

## Compound checks (--all)

Use `--all` to require multiple queries to ALL pass. Separate queries with `--`.

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE --all '<query1>' --min 1 -- '<query2>' --zero
```

Example: function exists AND all calls have 2+ args:

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE --all \
  '(function_declaration name:(identifier) @fn (#eq? @fn "greet"))' --min 1 \
  -- \
  '(call_expression function:(identifier) @fn arguments:(arguments (_) (_)) (#eq? @fn "greet"))' --min 2
```

## Raw queries (for edge cases)

When high-level checks don't cover your case, use a raw tree-sitter query:

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $FILE '<tree-sitter-query>' [--min N] [--max N] [--exact N] [--zero]
```

To discover the query structure, run `tree-sitter parse <file>` first.

## Writing good gates — more is better

**Overshoot on gates.** A quest with 10 tight gates is better than one with 3 loose ones. Each gate is cheap to run but expensive to cheat. When in doubt, add another gate.

Gates should verify MEANING, not just PRESENCE:

1. **Signature + defaults**: `--check fn-params greet name language="en"` not just "language exists"
2. **All call sites updated**: `--check call-min-args greet 2` not just "greet is called"
3. **Correct argument values**: `--check call-arg-matches greet 2 "es|fr|en"` not just "has 2 args"
4. **Imports actually used**: `--check import-used log` not just "log is imported"
5. **Assignments correct**: `--check assigned result greet` not just "result exists"
6. **Old patterns gone**: raw query with `--zero` for removed identifiers
7. **Compound relationships**: `--all` to enforce multiple properties together

### Tests as gates

Every quest that modifies code should include a gate verifying tests were added or updated. Use `check-ast` to verify the test FILE has the right structure:

```
${CLAUDE_PLUGIN_ROOT}/bin/check-ast $TEST_FILE --check symbol-used test_greet_language
```

This verifies a test function `test_greet_language` exists AND is referenced (not dead code). Do this for each test case you expect.

### Metagates — for complex or hard-to-verify work

Some changes are too complex to verify structurally (deep algorithmic changes, multi-file refactors with emergent behavior, protocol implementations). For these, add **metagates** — gates that verify the verification:

- **Test file exists**: raw query on the test file to check it was created
- **Test covers the change**: `--check symbol-used` on expected test function names
- **Test assertions present**: raw query for assertion nodes (`(call_expression function: (identifier) @fn (#match? @fn "assert|expect|should"))`)
- **Minimum test count**: raw query with `--min N` for the number of test functions

Example metagate set for a complex feature:

```json
{
  "name": "test file created for auth middleware",
  "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /path/test_auth.py '(function_definition name: (identifier) @fn (#match? @fn \"test_\"))' --min 3"
},
{
  "name": "tests include assertions",
  "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /path/test_auth.py '(call function: (attribute object: (_) attribute: (identifier) @m) (#match? @m \"assert|assertEqual|assertTrue\"))' --min 3"
},
{
  "name": "tests cover both success and failure paths",
  "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /path/test_auth.py --all '(function_definition name: (identifier) @fn (#match? @fn \"test_.*success|test_.*valid\"))' --min 1 -- '(function_definition name: (identifier) @fn (#match? @fn \"test_.*fail|test_.*invalid|test_.*error\"))' --min 1"
}
```

The principle: if you can't gate the implementation directly, gate the tests that verify the implementation. Tests are code — they have AST structure — they can be gated.

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

### Abandoning a quest

You cannot delete quest files. Only the user can. If gates are wrong or the task changed, tell the user to run:

```
! rm .claude/quests/<name>.json
```

The `!` prefix runs the command in the user's shell, outside of hooks.

## Complete example

Task: "Add a `language` parameter to `greet()` in `app.js`, default `"en"`, update both call sites"

```json
{
  "name": "add-language-param",
  "description": "Add language param to greet(), update both call sites",
  "created": "2026-03-25T00:00:00Z",
  "gates": [
    {
      "name": "greet() has name and language param with default en",
      "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /absolute/path/app.js --check fn-params greet name language=\"en\""
    },
    {
      "name": "all calls pass at least 2 arguments",
      "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /absolute/path/app.js --check call-min-args greet 2"
    },
    {
      "name": "second arg is a valid language code",
      "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /absolute/path/app.js --check call-arg-matches greet 2 \"en|es|fr\""
    },
    {
      "name": "greet is actually called (not just declared)",
      "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /absolute/path/app.js --check symbol-used greet"
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

Quest files are immutable after creation. Only the user can delete them.

## Lifecycle

1. Plan approved → hook fires → marker set
2. Gates defined with `check-ast` → marker cleared → edits unblocked
3. Work proceeds, commits are free
4. `git push` → all gates verified → auto-archived to `.claude/quests/done/`
5. Subagent return → gates verified → blocked if failing
