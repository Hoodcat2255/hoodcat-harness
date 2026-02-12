#!/usr/bin/env bash
# Integration test for Shared Context System hooks
# Runs each hook with mock input and verifies correct behavior.
# Usage: .claude/hooks/test-shared-context.sh [project-dir]
# exit 0 = all tests pass, exit 1 = some tests failed

set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
HOOKS_DIR="$PROJECT_DIR/.claude/hooks"
TEST_SESSION_ID="test-session-$(date +%s)"
CONTEXT_BASE="$PROJECT_DIR/.claude/shared-context"
TEST_DIR="$CONTEXT_BASE/$TEST_SESSION_ID"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0

assert_ok() {
  local desc="$1"
  local exit_code="$2"
  if [ "$exit_code" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (exit=$exit_code)"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_exists() {
  local desc="$1"
  local path="$2"
  if [ -d "$path" ]; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (directory not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local desc="$1"
  local path="$2"
  if [ -f "$path" ]; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_contains() {
  local desc="$1"
  local path="$2"
  local pattern="$3"
  if grep -q "$pattern" "$path" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (pattern not found: $pattern)"
    FAIL=$((FAIL + 1))
  fi
}

assert_valid_json() {
  local desc="$1"
  local output="$2"
  if echo "$output" | jq . &>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (invalid JSON)"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== Shared Context System Integration Tests ==="
echo "Project: $PROJECT_DIR"
echo "Session: $TEST_SESSION_ID"
echo ""

# --- Pre-check: dependencies ---
echo "[Pre-check] Dependencies"
if command -v jq &>/dev/null; then
  echo -e "  ${GREEN}PASS${NC}: jq installed"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: jq not installed (required for tests)"
  FAIL=$((FAIL + 1))
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  exit 1
fi

if command -v flock &>/dev/null; then
  echo -e "  ${GREEN}PASS${NC}: flock available"
  PASS=$((PASS + 1))
else
  echo -e "  ${YELLOW}WARN${NC}: flock not available (concurrent writes won't be locked)"
fi

# --- Test 1: cleanup.sh (SessionStart) ---
echo ""
echo "[Test 1] shared-context-cleanup.sh (SessionStart)"

CLEANUP_INPUT=$(jq -n --arg sid "$TEST_SESSION_ID" '{session_id: $sid}')
CLEANUP_EXIT=0
echo "$CLEANUP_INPUT" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$HOOKS_DIR/shared-context-cleanup.sh" > /dev/null 2>&1 || CLEANUP_EXIT=$?
assert_ok "Hook exits 0" "$CLEANUP_EXIT"
assert_dir_exists "Session directory created" "$TEST_DIR"

# --- Test 2: inject.sh (SubagentStart) - empty state ---
echo ""
echo "[Test 2] shared-context-inject.sh (SubagentStart) - empty state"

INJECT_INPUT=$(jq -n --arg sid "$TEST_SESSION_ID" '{
  session_id: $sid,
  agent_type: "navigator",
  agent_id: "test-nav-001",
  hook_event_name: "SubagentStart"
}')

INJECT_OUTPUT=""
INJECT_EXIT=0
INJECT_OUTPUT=$(echo "$INJECT_INPUT" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$HOOKS_DIR/shared-context-inject.sh" 2>/dev/null) || INJECT_EXIT=$?
assert_ok "Hook exits 0" "$INJECT_EXIT"
assert_valid_json "Output is valid JSON" "$INJECT_OUTPUT"

# Check that additionalContext contains write instruction
if echo "$INJECT_OUTPUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -q "shared-context"; then
  echo -e "  ${GREEN}PASS${NC}: additionalContext contains write instruction"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: additionalContext missing write instruction"
  FAIL=$((FAIL + 1))
fi

# --- Test 3: Simulate voluntary agent write ---
echo ""
echo "[Test 3] Simulate voluntary agent context write"

cat > "$TEST_DIR/navigator-test-nav-001.md" << 'EOF'
## Navigator Report
### Files Found
- /src/auth.ts - authentication module
- /src/db.ts - database connection
### Patterns
- JWT token-based auth
- Express middleware pattern
### Dependencies
- jsonwebtoken, express, pg
EOF

assert_file_exists "Agent context file created" "$TEST_DIR/navigator-test-nav-001.md"

# --- Test 4: collect.sh (SubagentStop) - voluntary context ---
echo ""
echo "[Test 4] shared-context-collect.sh (SubagentStop) - voluntary context"

COLLECT_INPUT=$(jq -n --arg sid "$TEST_SESSION_ID" '{
  session_id: $sid,
  agent_type: "navigator",
  agent_id: "test-nav-001",
  agent_transcript_path: "",
  hook_event_name: "SubagentStop"
}')

COLLECT_EXIT=0
echo "$COLLECT_INPUT" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$HOOKS_DIR/shared-context-collect.sh" > /dev/null 2>&1 || COLLECT_EXIT=$?
assert_ok "Hook exits 0" "$COLLECT_EXIT"
assert_file_exists "_summary.md created" "$TEST_DIR/_summary.md"
assert_file_contains "_summary.md has session header" "$TEST_DIR/_summary.md" "Shared Context Summary"
assert_file_contains "_summary.md has navigator entry" "$TEST_DIR/_summary.md" "navigator"

# --- Test 5: inject.sh (SubagentStart) - with existing context ---
echo ""
echo "[Test 5] shared-context-inject.sh (SubagentStart) - with existing context"

INJECT2_INPUT=$(jq -n --arg sid "$TEST_SESSION_ID" '{
  session_id: $sid,
  agent_type: "coder",
  agent_id: "test-coder-001",
  hook_event_name: "SubagentStart"
}')

INJECT2_OUTPUT=""
INJECT2_EXIT=0
INJECT2_OUTPUT=$(echo "$INJECT2_INPUT" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$HOOKS_DIR/shared-context-inject.sh" 2>/dev/null) || INJECT2_EXIT=$?
assert_ok "Hook exits 0" "$INJECT2_EXIT"
assert_valid_json "Output is valid JSON" "$INJECT2_OUTPUT"

# Check that summary content is included
if echo "$INJECT2_OUTPUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -q "navigator"; then
  echo -e "  ${GREEN}PASS${NC}: additionalContext includes navigator results"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: additionalContext missing navigator results"
  FAIL=$((FAIL + 1))
fi

# Check write instruction for coder
if echo "$INJECT2_OUTPUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -q "coder-test-coder-001"; then
  echo -e "  ${GREEN}PASS${NC}: additionalContext includes coder write path"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: additionalContext missing coder write path"
  FAIL=$((FAIL + 1))
fi

# --- Test 6: collect.sh - transcript fallback (no voluntary file) ---
echo ""
echo "[Test 6] shared-context-collect.sh (SubagentStop) - no voluntary file, no transcript"

COLLECT2_INPUT=$(jq -n --arg sid "$TEST_SESSION_ID" '{
  session_id: $sid,
  agent_type: "coder",
  agent_id: "test-coder-001",
  agent_transcript_path: "/nonexistent/transcript.jsonl",
  hook_event_name: "SubagentStop"
}')

COLLECT2_EXIT=0
echo "$COLLECT2_INPUT" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$HOOKS_DIR/shared-context-collect.sh" > /dev/null 2>&1 || COLLECT2_EXIT=$?
assert_ok "Hook exits 0" "$COLLECT2_EXIT"
assert_file_exists "Coder context file created (fallback)" "$TEST_DIR/coder-test-coder-001.md"
assert_file_contains "_summary.md updated with coder" "$TEST_DIR/_summary.md" "coder"

# --- Test 7: finalize.sh (SessionEnd) ---
echo ""
echo "[Test 7] shared-context-finalize.sh (SessionEnd)"

FINALIZE_INPUT=$(jq -n --arg sid "$TEST_SESSION_ID" '{session_id: $sid}')
FINALIZE_EXIT=0
echo "$FINALIZE_INPUT" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$HOOKS_DIR/shared-context-finalize.sh" > /dev/null 2>&1 || FINALIZE_EXIT=$?
assert_ok "Hook exits 0" "$FINALIZE_EXIT"
assert_file_contains "_summary.md has finalization metadata" "$TEST_DIR/_summary.md" "Session finalized"

# --- Test 8: concurrent write test (flock) ---
echo ""
echo "[Test 8] Concurrent write safety (flock)"

if command -v flock &>/dev/null; then
  # Run two collect hooks in parallel
  PARA_INPUT1=$(jq -n --arg sid "$TEST_SESSION_ID" '{
    session_id: $sid,
    agent_type: "reviewer",
    agent_id: "test-rev-001",
    agent_transcript_path: "",
    hook_event_name: "SubagentStop"
  }')
  PARA_INPUT2=$(jq -n --arg sid "$TEST_SESSION_ID" '{
    session_id: $sid,
    agent_type: "security",
    agent_id: "test-sec-001",
    agent_transcript_path: "",
    hook_event_name: "SubagentStop"
  }')

  # Create voluntary files for both
  echo -e "## Reviewer Report\n### Verdict\n- PASS" > "$TEST_DIR/reviewer-test-rev-001.md"
  echo -e "## Security Report\n### Verdict\n- PASS" > "$TEST_DIR/security-test-sec-001.md"

  # Run in parallel
  PARA_EXIT1=0
  PARA_EXIT2=0
  echo "$PARA_INPUT1" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$HOOKS_DIR/shared-context-collect.sh" > /dev/null 2>&1 &
  PID1=$!
  echo "$PARA_INPUT2" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$HOOKS_DIR/shared-context-collect.sh" > /dev/null 2>&1 &
  PID2=$!

  wait $PID1 || PARA_EXIT1=$?
  wait $PID2 || PARA_EXIT2=$?

  assert_ok "Parallel hook 1 exits 0" "$PARA_EXIT1"
  assert_ok "Parallel hook 2 exits 0" "$PARA_EXIT2"
  assert_file_contains "_summary.md has reviewer entry" "$TEST_DIR/_summary.md" "reviewer"
  assert_file_contains "_summary.md has security entry" "$TEST_DIR/_summary.md" "security"
else
  echo -e "  ${YELLOW}SKIP${NC}: flock not available, skipping concurrent test"
fi

# --- Cleanup test data ---
echo ""
echo "[Cleanup] Removing test session directory"
rm -rf "$TEST_DIR"
echo -e "  ${GREEN}PASS${NC}: Test directory cleaned up"
PASS=$((PASS + 1))

# --- Results ---
echo ""
echo "=== Results ==="
echo -e "  ${GREEN}Passed${NC}: $PASS"
if [ "$FAIL" -gt 0 ]; then
  echo -e "  ${RED}Failed${NC}: $FAIL"
else
  echo -e "  Failed: $FAIL"
fi
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}Some tests failed!${NC}"
  exit 1
else
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi
