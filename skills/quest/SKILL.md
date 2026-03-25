---
name: quest
description: Create and manage quests — mechanically enforced task gates. Use when starting any task that modifies code, to guarantee completion. Subcommands - create, check, list, done, abandon.
user_invocable: true
---

# Quests

Quests are mechanically enforced task contracts. Each quest defines **gates** — shell commands that must exit 0. Hooks block `git commit` and `git push` until every active gate passes. The Stop hook warns you if you try to finish with failing gates.

Quest files live at `.claude/quests/<name>.json` in the project directory.

## Subcommands

Parse the user's argument to determine which subcommand to run:

### `/quest` or `/quest list`
List all active quests and run their gates to show current status.

For each quest file in `.claude/quests/*.json`:
1. Read the quest
2. Run each gate's `check` command (in the project directory, with `timeout 30`)
3. Display:
```
Quest: <name> — <description>
  ✓ gate name
  ✗ gate name
    check: <the failing command>
```

### `/quest create`
Create a new quest for the current task. Steps:

1. Ask the user what the task is (or infer from recent conversation context)
2. Analyze the task and design gates
3. Present the quest to the user for approval
4. On approval, write to `.claude/quests/<name>.json`

### `/quest check`
Same as `list` but re-runs all gates and shows verbose output for failures (include stderr).

### `/quest done <name>`
1. Run all gates for the named quest
2. If ALL pass: move to `.claude/quests/done/<name>.json`, report completion
3. If ANY fail: refuse, show which failed

### `/quest abandon <name>`
Remove the quest file without verification. For when the task changes or gates are wrong.

## Creating Gates — CRITICAL RULES

Gates are the entire point. Bad gates = no enforcement. Follow these rules:

### 1. Check the substance, not the form
BAD: `grep -q 'newParam' src/handler.ts` — catches a comment, a string, anything
GOOD: `grep -qP 'function processRequest\(.*timeout:\s*number' src/handler.ts` — checks actual signature

### 2. Check both sides of a change
If adding a param, verify BOTH:
- The declaration has it: `grep -qP 'function fn\(.*newParam' src/module.ts`
- Call sites use it: `test $(grep -rn 'fn(' src/ --include='*.ts' | grep -v 'function fn' | grep -v newParam | wc -l) -eq 0`

### 3. Use negative checks to catch staleness
`! grep -rq 'oldPattern' src/` — verify the OLD thing is gone, not just that the new thing exists.

### 4. Count when counts matter
`test $(grep -c 'fn(.*newParam)' src/ -r --include='*.ts') -ge 5` — if there are 5 call sites, verify 5 updates.

### 5. Run tests when they exist
`cd "$PROJECT_DIR" && npm test` or `cargo test` — the test suite IS a gate.

### 6. Use scripts for complex checks
For anything beyond grep, write a small inline script:
```bash
node -e "const src = require('fs').readFileSync('src/handler.ts','utf8'); const match = src.match(/function processRequest\((.*?)\)/); if (!match || !match[1].includes('timeout')) process.exit(1);"
```

### 7. Be specific about file paths
Don't glob the entire repo. Target the specific files that should change.

### 8. Timeout every check
All checks run with `timeout 30`. If your check needs more than 30s, it's too expensive for a gate.

## Quest File Format

```json
{
  "name": "descriptive-kebab-name",
  "description": "One-line description of what this quest verifies",
  "created": "2026-03-24T00:00:00Z",
  "gates": [
    {
      "name": "human-readable gate description",
      "check": "shell command that exits 0 on success"
    }
  ]
}
```

## Directory Structure

```
.claude/quests/
  add-timeout-param.json     # active quest
  fix-auth-middleware.json    # active quest
  done/
    migrate-database.json    # completed quest (archived)
```

Create `.claude/quests/` and `.claude/quests/done/` as needed.

## Example Quest

Task: "Add a `timeout` parameter to `processRequest()` and pass it at all call sites"

```json
{
  "name": "add-timeout-param",
  "description": "Add timeout param to processRequest and update all 4 call sites",
  "created": "2026-03-24T00:00:00Z",
  "gates": [
    {
      "name": "processRequest signature has timeout param",
      "check": "grep -qP 'function processRequest\\(.*timeout' src/handler.ts"
    },
    {
      "name": "no call sites without timeout arg",
      "check": "test $(grep -rn 'processRequest(' src/ --include='*.ts' | grep -v 'function processRequest' | grep -v timeout | wc -l) -eq 0"
    },
    {
      "name": "timeout param has correct type",
      "check": "grep -qP 'timeout:\\s*number' src/handler.ts"
    },
    {
      "name": "tests pass",
      "check": "cd /path/to/project && npm test 2>&1"
    }
  ]
}
```
