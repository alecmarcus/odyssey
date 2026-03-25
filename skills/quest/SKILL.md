---
name: quest
description: Create and manage quests — mechanically enforced task gates. Use when starting any task that modifies code, to guarantee completion. Subcommands - create, check, list, done, abandon.
user_invocable: true
---

# Quests

Quests are mechanically enforced task contracts. Each quest defines **gates** — shell commands that must exit 0. Hooks block `git commit`, `git push`, and `stop` until every active gate passes.

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
2. Parse intent into a structured pattern (see Gate Templates below)
3. Generate gates mechanically from templates
4. Present the quest to the user for approval
5. On approval, write to `.claude/quests/<name>.json`

### `/quest check`
Same as `list` but re-runs all gates and shows verbose output for failures (include stderr).

### `/quest done <name>`
1. Run all gates for the named quest
2. If ALL pass: move to `.claude/quests/done/<name>.json`, report completion
3. If ANY fail: refuse, show which failed

### `/quest abandon <name>`
Remove the quest file without verification. For when the task changes or gates are wrong.

## Gate Templates

Generate gates from these templates. Do NOT write gates from scratch — match the task to a template and fill in the blanks.

IMPORTANT: Use `grep -E` (extended regex), NOT `grep -P` (Perl regex). macOS BSD grep does not support `-P`.

### ADD PARAM: Add parameter `$PARAM` to function `$FN` in `$FILE`, update call sites

```json
[
  {
    "name": "$FN() signature has $PARAM param",
    "check": "grep -qE '(def|function|fn|pub fn) $FN\\(.*$PARAM' $FILE"
  },
  {
    "name": "all call sites pass $PARAM",
    "check": "test $(grep -E '$FN\\(' $FILE | grep -v '(def |function |fn |pub fn )' | grep -v '$PARAM' | wc -l | tr -d ' ') -eq 0"
  },
  {
    "name": "expected number of call sites updated",
    "check": "test $(grep -E '$FN\\(.*$PARAM' $FILE | grep -v '(def |function |fn |pub fn )' | wc -l | tr -d ' ') -ge $COUNT"
  }
]
```

### RENAME: Rename `$OLD` to `$NEW` across `$GLOB`

```json
[
  {
    "name": "$OLD is gone from all source files",
    "check": "test $(grep -rE '$OLD' $GLOB | wc -l | tr -d ' ') -eq 0"
  },
  {
    "name": "$NEW exists in expected files",
    "check": "grep -rqE '$NEW' $GLOB"
  }
]
```

### MOVE FILE: Move `$SRC` to `$DST`, update imports

```json
[
  {
    "name": "old file is gone",
    "check": "test ! -f $SRC"
  },
  {
    "name": "new file exists",
    "check": "test -f $DST"
  },
  {
    "name": "no imports reference old path",
    "check": "test $(grep -rE '(import|require|from).*$OLD_MODULE' $GLOB | wc -l | tr -d ' ') -eq 0"
  }
]
```

### ADD FILE: Create `$FILE` with required content

```json
[
  {
    "name": "file exists",
    "check": "test -f $FILE"
  },
  {
    "name": "file contains required pattern",
    "check": "grep -qE '$PATTERN' $FILE"
  }
]
```

### DELETE: Remove `$PATTERN` from `$GLOB`

```json
[
  {
    "name": "$PATTERN is gone",
    "check": "test $(grep -rE '$PATTERN' $GLOB | wc -l | tr -d ' ') -eq 0"
  }
]
```

### TESTS PASS

```json
[
  {
    "name": "test suite passes",
    "check": "cd $PROJECT && $TEST_CMD"
  }
]
```

### CUSTOM: For anything not covered above

Write a gate using `grep -E`, `test`, or an inline script. Follow the rules below.

## Gate Rules

1. **Use templates first.** Only write custom gates when no template fits.
2. **Check substance, not form.** Match the function/class/signature, not just a keyword.
3. **Check both sides.** Verify the new thing exists AND the old thing is gone.
4. **Count when counts matter.** If there are N call sites, verify N updates.
5. **Use `grep -E`**, not `grep -P`. macOS compatibility.
6. **Be specific about paths.** Don't glob the entire repo.
7. **Always add a test gate** when the project has a test suite.
8. **Inline scripts** for complex checks: `node -e "..."`, `python3 -c "..."`.

## Quest File Format

```json
{
  "name": "descriptive-kebab-name",
  "description": "One-line description of what this quest verifies",
  "created": "ISO-8601",
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
  active-quest.json
  done/
    completed-quest.json
```

Create directories as needed.
