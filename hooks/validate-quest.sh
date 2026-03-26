#!/usr/bin/env bash
# PreToolUse on Write: validates quest files before they're written.
# Validates JSON structure and immutability. No gate-type restrictions.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only validate writes to quest files
if ! echo "$FILE_PATH" | grep -q '\.claude/quests/.*\.json$'; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Allow writes to done/ subdir (archiving)
if echo "$FILE_PATH" | grep -q '\.claude/quests/done/'; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Quest files are immutable. Only the user can remove them.
if [ -f "$FILE_PATH" ]; then
  echo '{"decision":"block","reason":"BLOCKED: Quest files are immutable. Ask the user to delete it: ! rm .claude/quests/<name>.json"}'
  exit 0
fi

CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)

if ! echo "$CONTENT" | jq -e '.gates' >/dev/null 2>&1; then
  echo '{"decision":"block","reason":"BLOCKED: Quest file must be valid JSON with a \"gates\" array."}'
  exit 0
fi

echo '{"decision":"allow"}'
