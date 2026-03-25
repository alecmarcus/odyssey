#!/usr/bin/env bash
# PostToolUse on ExitPlanMode: sets marker + injects gate-creation requirement.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
QUEST_DIR="$PROJECT_DIR/.claude/quests"

mkdir -p "$QUEST_DIR"
touch "$QUEST_DIR/.plan-pending"

cat << 'MSG'
MANDATORY: You approved a plan. Before writing ANY code, you MUST:

1. Parse each concrete deliverable in the plan
2. For each, generate verifiable quest gates using the odyssey gate templates (ADD PARAM, RENAME, MOVE, DELETE, ADD FILE, TESTS PASS)
3. Write the quest to .claude/quests/<name>.json
4. Present the quest to the user for approval

You CANNOT edit source files until quest gates are defined. The harness will block you.
MSG
