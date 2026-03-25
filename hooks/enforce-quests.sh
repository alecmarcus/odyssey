#!/usr/bin/env bash
# PreToolUse hook (Bash): blocks git commit/push when quest gates are failing.
# No active quests = no-op (allow everything).

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Block deletion of quest files
if echo "$COMMAND" | grep -qE '(rm|unlink)' && echo "$COMMAND" | grep -q '\.claude/quests'; then
  echo '{"decision":"block","reason":"BLOCKED: Cannot delete quest files via shell. Use /quest abandon to remove a quest."}'
  exit 0
fi

# Only gate on git commit and git push (anywhere in the command, catches chains)
if ! echo "$COMMAND" | grep -qE 'git\s+(commit|push)'; then
  echo '{"decision":"allow"}'
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
_MAIN_TREE=$(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')
QUEST_DIR="${_MAIN_TREE:-$PROJECT_DIR}/.claude/quests"

# No quest dir or no quest files = allow
if [ ! -d "$QUEST_DIR" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

QUEST_FILES=("$QUEST_DIR"/*.json)
if [ ! -f "${QUEST_FILES[0]:-}" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Run every gate in every active quest
FAILURES=""
for quest_file in "${QUEST_FILES[@]}"; do
  [ -f "$quest_file" ] || continue

  QUEST_NAME=$(jq -r '.name // "unnamed"' "$quest_file" 2>/dev/null)

  while IFS= read -r gate; do
    GATE_NAME=$(echo "$gate" | jq -r '.name // "unnamed gate"')
    GATE_CHECK=$(echo "$gate" | jq -r '.check // "false"')

    # Run check with 30s timeout, in project dir
    if ! (cd "$PROJECT_DIR" && timeout 30 bash -c "$GATE_CHECK") >/dev/null 2>&1; then
      FAILURES="${FAILURES}  ✗ [${QUEST_NAME}] ${GATE_NAME}\n"
    fi
  done < <(jq -c '.gates[]' "$quest_file" 2>/dev/null)
done

if [ -n "$FAILURES" ]; then
  REASON=$(printf 'BLOCKED: Quest gates are failing. You cannot commit/push until ALL gates pass.\n\nFailing gates:\n%bFix these issues and retry. Run /quest check for details.' "$FAILURES")
  REASON_JSON=$(echo "$REASON" | jq -Rs '.')
  echo "{\"decision\":\"block\",\"reason\":${REASON_JSON}}"
else
  # All gates pass — auto-archive completed quests
  if echo "$COMMAND" | grep -qE 'git\s+commit'; then
    mkdir -p "$QUEST_DIR/done"
    echo 'done/' > "$QUEST_DIR/.gitignore" 2>/dev/null || true
    for quest_file in "${QUEST_FILES[@]}"; do
      [ -f "$quest_file" ] || continue
      mv "$quest_file" "$QUEST_DIR/done/"
    done
    rm -f "$QUEST_DIR/.plan-pending"
  fi
  echo '{"decision":"allow"}'
fi
