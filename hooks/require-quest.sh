#!/usr/bin/env bash
# PreToolUse on Edit/Write: blocks code edits when a plan was approved but no quest gates exist.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
QUEST_DIR="$PROJECT_DIR/.claude/quests"
MARKER="$QUEST_DIR/.plan-pending"

# No marker = no plan-based requirement
if [ ! -f "$MARKER" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Always allow writes to the quest directory itself (creating quest files)
if echo "$FILE_PATH" | grep -q '\.claude/quests'; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Marker exists — check if quests have been created
QUEST_FILES=("$QUEST_DIR"/*.json)
if [ -f "${QUEST_FILES[0]:-}" ]; then
  # Quests defined, clear marker, allow
  rm -f "$MARKER"
  echo '{"decision":"allow"}'
  exit 0
fi

# Plan approved, no quests yet — block
echo '{"decision":"block","reason":"BLOCKED: Plan was approved but no quest gates are defined. You must create quest gates from the plan before editing code. Write a quest file to .claude/quests/<name>.json first."}'
