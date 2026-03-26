---
name: quest
description: Create and manage quests — mechanically enforced task gates that block push and subagent return until all gates pass. Subcommands - create, check, list, done.
user_invocable: true
---

# Quests

Quests are mechanically enforced task contracts. Each quest defines **gates** — shell commands that must exit 0. Hooks block `git push` and subagent return until every gate passes. Quests auto-archive on push. Quest files are immutable once created.

Quest files live at `.claude/quests/<name>.json` in the project directory.

## CRITICAL: Gate philosophy

### Behavioral gates are primary

The most important gates are **behavioral tests** — commands that exercise the feature and verify it works. A behavioral gate runs the code and checks the output. You cannot fake behavior.

```
cd $PROJECT && cargo test test_budget_enforcement
cd $PROJECT && npm test -- --grep "deducts cost"
cd $PROJECT && python3 -m pytest tests/test_auth.py::test_rejects_expired_token -x
```

An agent can produce a perfectly structured `evaluate_cost()` call that passes every AST check while passing `&[]` as the data. It cannot fake a test that creates a paid context, sends a message, and asserts the budget decreased.

### AST gates are supplementary

Use `check-ast` (tree-sitter queries) to catch structural omissions — missing parameters, stale call sites, dead imports. These are the safety net, not the definition of done.

### More gates are better

A quest with 15 gates is better than one with 5. Each gate is cheap to run. Layer behavioral tests, structural checks, and metagates together.

### Do not show gate details to implementing agents

If you are an orchestrator dispatching work to subagents: give the subagent the **spec**, not the gates. The spec describes what to build. The gates silently verify it was built. Showing the agent the exact AST patterns is teaching to the test — they will satisfy the pattern without implementing the behavior.

## Gate types

### 1. Behavioral gates (PRIMARY)

Shell commands that run tests or exercise the code. These are the gates that matter most.

```json
{
  "name": "budget enforcement works",
  "check": "cd /path/to/project && cargo test test_budget_blocks_when_exceeded -- --nocapture"
}
```

```json
{
  "name": "API returns 401 for expired tokens",
  "check": "cd /path/to/project && npm test -- --grep 'expired token' --exit"
}
```

```json
{
  "name": "script runs without error",
  "check": "cd /path/to/project && python3 -c 'from auth import validate_token; assert validate_token(\"expired\") == False'"
}
```

### 2. Structural gates (SUPPLEMENTARY)

Tree-sitter AST queries via `check-ast`. Catch structural omissions. Use the `--check` high-level commands or raw queries.

```json
{
  "name": "evaluate_cost has budget param",
  "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /path/file.rs --check fn-params evaluate_cost rules events context"
}
```

```json
{
  "name": "all call sites pass 3 args",
  "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /path/file.rs --check call-min-args evaluate_cost 3"
}
```

High-level `--check` commands: `fn-params`, `call-min-args`, `call-arg-matches`, `symbol-used`, `import-used`, `assigned`. See `check-ast --help` or run `${CLAUDE_PLUGIN_ROOT}/bin/check-ast` with no args for usage.

Compound: `--all '<q1>' --min N -- '<q2>' --zero` requires all queries pass.

Raw: `${CLAUDE_PLUGIN_ROOT}/bin/check-ast <file> '<tree-sitter-query>' [--min N|--zero]`. Run `tree-sitter parse <file>` to discover node types.

### 3. Metagates (ADDITIVE)

Verify tests were written. Always added alongside behavioral and structural gates, never instead of.

```json
{
  "name": "test file has 3+ test functions",
  "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /path/test_file.py '(function_definition name: (identifier) @fn (#match? @fn \"test_\"))' --min 3"
}
```

```json
{
  "name": "tests cover success and failure paths",
  "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /path/test_file.py --all '(function_definition name: (identifier) @fn (#match? @fn \"test_.*success|test_.*valid\"))' --min 1 -- '(function_definition name: (identifier) @fn (#match? @fn \"test_.*fail|test_.*invalid|test_.*error\"))' --min 1"
}
```

## Writing a quest

A good quest layers all three gate types:

1. **Behavioral**: test commands that exercise the feature end-to-end
2. **Structural**: AST checks that the code has the right shape (params, call sites, imports)
3. **Meta**: AST checks that tests exist and cover the right cases

All code is AST. There is no implementation too complex to gate structurally. But structure alone is not sufficient — behavior is what matters.

## Subcommands

### `/quest` or `/quest list`

List active quests, run gates, show pass/fail.

### `/quest create`

1. Ask the user what the task is (or infer from context)
2. Design behavioral gates first — what tests prove the feature works?
3. Add structural gates — what AST properties must hold?
4. Add metagates — what tests must exist?
5. Present quest for user approval
6. Write to `.claude/quests/<name>.json`

### `/quest check`

Re-run all gates with verbose failure output.

### `/quest done <name>`

Run all gates. If ALL pass, archive to `.claude/quests/done/`. Refuse if any fail.

### Abandoning a quest

You cannot delete quest files. Only the user can. If gates are wrong or the task changed, tell the user to run:

```
! rm .claude/quests/<name>.json
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
      "check": "shell command that exits 0 on success"
    }
  ]
}
```

Quest files are immutable after creation. Only the user can delete them.

## Complete example

Task: "Add budget enforcement to message sending — block messages when cost exceeds budget"

```json
{
  "name": "budget-enforcement",
  "description": "Block message sending when cost exceeds budget",
  "created": "2026-03-26T00:00:00Z",
  "gates": [
    {
      "name": "test: message blocked when budget exceeded",
      "check": "cd /path/project && cargo test test_message_blocked_when_budget_exceeded"
    },
    {
      "name": "test: message allowed when budget available",
      "check": "cd /path/project && cargo test test_message_sent_when_budget_available"
    },
    {
      "name": "test: budget decremented after send",
      "check": "cd /path/project && cargo test test_budget_decremented_after_send"
    },
    {
      "name": "evaluate_cost has correct params",
      "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /path/handler.rs --check fn-params evaluate_cost rules events context"
    },
    {
      "name": "evaluate_cost is called in send_message",
      "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /path/handler.rs --check symbol-used evaluate_cost"
    },
    {
      "name": "budget field exists on context struct",
      "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /path/types.rs '(field_declaration name: (field_identifier) @f (#eq? @f \"budget\"))'"
    },
    {
      "name": "test file has 3+ test functions",
      "check": "${CLAUDE_PLUGIN_ROOT}/bin/check-ast /path/tests.rs '(function_item name: (identifier) @fn (#match? @fn \"test_\"))' --min 3"
    }
  ]
}
```

Behavioral gates first (3 tests), structural gates second (3 AST checks), metagate last (test count).

## Lifecycle

1. Plan approved → hook fires → marker set
2. Gates defined → marker cleared → edits unblocked
3. Work proceeds, commits are free
4. `git push` → all gates verified → auto-archived to `.claude/quests/done/`
5. Subagent return → gates verified → blocked if failing
