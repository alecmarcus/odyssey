#!/usr/bin/env bash
# Stop hook: BLOCKS stop when active quest gates are failing.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
QUEST_DIR="$PROJECT_DIR/.claude/quests"

if [ ! -d "$QUEST_DIR" ]; then
  exit 0
fi

QUEST_FILES=("$QUEST_DIR"/*.json)
if [ ! -f "${QUEST_FILES[0]:-}" ]; then
  exit 0
fi

FAILURES=""
for quest_file in "${QUEST_FILES[@]}"; do
  [ -f "$quest_file" ] || continue

  QUEST_NAME=$(jq -r '.name // "unnamed"' "$quest_file" 2>/dev/null)

  while IFS= read -r gate; do
    GATE_NAME=$(echo "$gate" | jq -r '.name // "unnamed gate"')
    GATE_CHECK=$(echo "$gate" | jq -r '.check // "false"')

    if ! (cd "$PROJECT_DIR" && timeout 30 bash -c "$GATE_CHECK") >/dev/null 2>&1; then
      FAILURES="${FAILURES}  ✗ [${QUEST_NAME}] ${GATE_NAME}\n"
    fi
  done < <(jq -c '.gates[]' "$quest_file" 2>/dev/null)
done

if [ -n "$FAILURES" ]; then
  REASON=$(printf 'BLOCKED: Quest gates are failing. You are not done.\n\nFailing gates:\n%bFix all failing gates before stopping.' "$FAILURES")
  REASON_JSON=$(echo "$REASON" | jq -Rs '.')
  echo "{\"decision\":\"block\",\"reason\":${REASON_JSON}}"
fi
