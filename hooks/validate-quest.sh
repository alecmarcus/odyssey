#!/usr/bin/env bash
# PreToolUse on Write: validates quest files before they're written.
# Every gate must use check-ast OR be a runtime test (test suite, interpreter).
# No grep, no awk, no sed, no regex on text. No exceptions.

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

CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)

if ! echo "$CONTENT" | jq -e '.gates' >/dev/null 2>&1; then
  echo '{"decision":"block","reason":"BLOCKED: Quest file must be valid JSON with a \"gates\" array."}'
  exit 0
fi

# Allowed runtime commands (test suites, interpreters — not structural checks)
# These run the code, they don't inspect it textually.
RUNTIME_PATTERN='(npm test|npx |yarn test|pnpm test|cargo test|cargo check|cargo build|pytest|python3? -[cm]|python3? .*\.py|node .*\.(js|mjs|ts)|go test|go build|swift test|swift build|make |cmake |tsc |eslint |mypy |ruff )'

REJECTED=""
while IFS= read -r gate; do
  GATE_NAME=$(echo "$gate" | jq -r '.name // "unnamed"')
  GATE_CHECK=$(echo "$gate" | jq -r '.check // ""')

  # check-ast gates — always allowed
  if echo "$GATE_CHECK" | grep -q 'check-ast'; then
    continue
  fi

  # Runtime/build/test commands — allowed
  if echo "$GATE_CHECK" | grep -qE "$RUNTIME_PATTERN"; then
    continue
  fi

  # Everything else is rejected
  REJECTED="${REJECTED}  ✗ \"${GATE_NAME}\": $(echo "$GATE_CHECK" | head -c 120)\n"

done < <(echo "$CONTENT" | jq -c '.gates[]' 2>/dev/null)

if [ -n "$REJECTED" ]; then
  REASON=$(printf 'BLOCKED: Every structural gate must use check-ast (tree-sitter). Only test/build commands are exempt.\n\nRejected gates:\n%b\nRewrite using: ${CLAUDE_PLUGIN_ROOT}/bin/check-ast <file> '\''<tree-sitter-query>'\'' [--min N|--zero]\nRun \"tree-sitter parse <file>\" first to see the AST node types.' "$REJECTED")
  REASON_JSON=$(echo "$REASON" | jq -Rs '.')
  echo "{\"decision\":\"block\",\"reason\":${REASON_JSON}}"
else
  echo '{"decision":"allow"}'
fi
