#!/usr/bin/env bash
# PreToolUse on Write: validates quest files before they're written.
# Every gate must use check-ast. Nothing else. No exceptions.

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

REJECTED=""
while IFS= read -r gate; do
  GATE_NAME=$(echo "$gate" | jq -r '.name // "unnamed"')
  GATE_CHECK=$(echo "$gate" | jq -r '.check // ""')

  if ! echo "$GATE_CHECK" | grep -q 'check-ast'; then
    REJECTED="${REJECTED}  ✗ \"${GATE_NAME}\": $(echo "$GATE_CHECK" | head -c 120)\n"
  fi

done < <(echo "$CONTENT" | jq -c '.gates[]' 2>/dev/null)

if [ -n "$REJECTED" ]; then
  REASON=$(printf 'BLOCKED: Every gate must use check-ast (tree-sitter). No exceptions.\n\nRejected gates:\n%b\nRewrite using: ${CLAUDE_PLUGIN_ROOT}/bin/check-ast <file> '\''<tree-sitter-query>'\'' [--min N|--zero]\nRun \"tree-sitter parse <file>\" first to see the AST node types.' "$REJECTED")
  REASON_JSON=$(echo "$REASON" | jq -Rs '.')
  echo "{\"decision\":\"block\",\"reason\":${REASON_JSON}}"
else
  echo '{"decision":"allow"}'
fi
