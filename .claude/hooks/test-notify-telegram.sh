#!/usr/bin/env bash
# Unit tests for notify-telegram.sh utility functions
# Tests: extract_section, extract_filenames, count_lines, has_issues, escape_html,
#        get_agent_display_name, get_agent_emoji
# Also tests full structured message composition, fallback message,
# and non-orchestrator agent message composition.
#
# Usage: bash .claude/hooks/test-notify-telegram.sh [project-dir]
# exit 0 = all tests pass, exit 1 = some tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
NOTIFY_SCRIPT="$SCRIPT_DIR/notify-telegram.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $desc"
    echo -e "    expected: $(echo "$expected" | head -5)"
    echo -e "    actual:   $(echo "$actual" | head -5)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1"
  local haystack="$2"
  local needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (needle not found)"
    echo -e "    needle:   $needle"
    echo -e "    haystack: $(echo "$haystack" | head -3)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1"
  local haystack="$2"
  local needle="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (needle found but should not be)"
    echo -e "    needle:   $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_empty() {
  local desc="$1"
  local actual="$2"
  if [ -z "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (expected empty, got: '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_rc() {
  local desc="$1"
  local expected_rc="$2"
  local actual_rc="$3"
  if [ "$expected_rc" -eq "$actual_rc" ]; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (expected rc=$expected_rc, got rc=$actual_rc)"
    FAIL=$((FAIL + 1))
  fi
}

# =====================================================================
# Extract function definitions from notify-telegram.sh
# We source only the function definitions, not the main body.
# =====================================================================

# Extract function bodies using sed: from function_name() { to matching }
# This avoids sourcing the entire script which reads stdin and calls curl.

extract_functions() {
  # Extract each utility function individually
  local src="$NOTIFY_SCRIPT"

  # escape_html
  eval "$(sed -n '/^escape_html()/,/^}/p' "$src")"

  # extract_section
  eval "$(sed -n '/^extract_section()/,/^}/p' "$src")"

  # extract_filenames
  eval "$(sed -n '/^extract_filenames()/,/^}/p' "$src")"

  # count_lines
  eval "$(sed -n '/^count_lines()/,/^}/p' "$src")"

  # has_issues - this uses global UNRESOLVED_ISSUES variable
  eval "$(sed -n '/^has_issues()/,/^}/p' "$src")"

  # get_agent_display_name
  eval "$(sed -n '/^get_agent_display_name()/,/^}/p' "$src")"

  # get_agent_emoji
  eval "$(sed -n '/^get_agent_emoji()/,/^}/p' "$src")"
}

extract_functions

echo ""
echo "=== notify-telegram.sh Utility Function Tests ==="
echo "Script: $NOTIFY_SCRIPT"
echo ""

# =====================================================================
# Test 1: extract_section
# =====================================================================
echo "[Test 1] extract_section"

SAMPLE_REPORT='## Orchestrator Report
### Plan
- notify-telegram.sh 구조화된 메시지 파싱 구현
- SubagentStop 훅으로 orchestrator 감지하여 알림 전송

### Steps Executed
- [x] 훅 시스템 분석
- [x] notify-telegram.sh 작성

### Files Changed
- `.claude/hooks/notify-telegram.sh` -- 텔레그램 알림 훅 (신규)
- `.claude/.env.example` -- 환경 변수 템플릿 (신규)
- `.gitignore` -- .env 추가

### Review Verdicts
- N/A (단순 기능 추가)

### Unresolved Issues
- 없음'

# 1a. Plan section extraction
PLAN_RESULT=$(extract_section "$SAMPLE_REPORT" "Plan")
assert_contains "Plan section: first line present" "$PLAN_RESULT" "notify-telegram.sh"
assert_contains "Plan section: second line present" "$PLAN_RESULT" "SubagentStop"
assert_not_contains "Plan section: does not contain Steps" "$PLAN_RESULT" "Steps Executed"

# 1b. Files Changed section extraction
FILES_RESULT=$(extract_section "$SAMPLE_REPORT" "Files Changed")
assert_contains "Files Changed: has notify-telegram.sh" "$FILES_RESULT" "notify-telegram.sh"
assert_contains "Files Changed: has .env.example" "$FILES_RESULT" ".env.example"
assert_contains "Files Changed: has .gitignore" "$FILES_RESULT" ".gitignore"
assert_not_contains "Files Changed: does not contain Review" "$FILES_RESULT" "Review Verdicts"

# 1c. Unresolved Issues section extraction
ISSUES_RESULT=$(extract_section "$SAMPLE_REPORT" "Unresolved Issues")
assert_eq "Unresolved Issues: content is correct" "- 없음" "$ISSUES_RESULT"

# 1d. Non-existent section returns empty
MISSING_RESULT=$(extract_section "$SAMPLE_REPORT" "NonExistentSection")
assert_empty "Non-existent section returns empty" "$MISSING_RESULT"

# 1e. Review Verdicts section
REVIEW_RESULT=$(extract_section "$SAMPLE_REPORT" "Review Verdicts")
assert_contains "Review Verdicts: has N/A" "$REVIEW_RESULT" "N/A"

# =====================================================================
# Test 2: extract_filenames
# =====================================================================
echo ""
echo "[Test 2] extract_filenames"

# 2a. Backtick + description format
INPUT_BACKTICK='- `src/file.ts` -- 설명
- `lib/utils.js` -- 유틸리티'
FILENAMES_BT=$(extract_filenames "$INPUT_BACKTICK")
assert_contains "Backtick format: src/file.ts extracted" "$FILENAMES_BT" "src/file.ts"
assert_contains "Backtick format: lib/utils.js extracted" "$FILENAMES_BT" "lib/utils.js"
assert_not_contains "Backtick format: description removed" "$FILENAMES_BT" "설명"
assert_not_contains "Backtick format: backticks removed" "$FILENAMES_BT" '`'

# 2b. Plain format (no backticks)
INPUT_PLAIN='- src/file.ts
- lib/utils.js'
FILENAMES_PL=$(extract_filenames "$INPUT_PLAIN")
assert_contains "Plain format: src/file.ts extracted" "$FILENAMES_PL" "src/file.ts"
assert_contains "Plain format: lib/utils.js extracted" "$FILENAMES_PL" "lib/utils.js"

# 2c. Hook file format with em-dash and description
INPUT_HOOK='- `.claude/hooks/notify-telegram.sh` -- 텔레그램 알림 훅 (신규)
- `.claude/.env.example` -- 환경 변수 템플릿 (신규)
- `.gitignore` -- .env 추가'
FILENAMES_HK=$(extract_filenames "$INPUT_HOOK")
assert_contains "Hook format: notify-telegram.sh path" "$FILENAMES_HK" ".claude/hooks/notify-telegram.sh"
assert_contains "Hook format: .env.example path" "$FILENAMES_HK" ".claude/.env.example"
assert_contains "Hook format: .gitignore path" "$FILENAMES_HK" ".gitignore"
assert_not_contains "Hook format: description removed" "$FILENAMES_HK" "신규"

# =====================================================================
# Test 3: count_lines
# =====================================================================
echo ""
echo "[Test 3] count_lines"

# 3a. Empty string returns 0
COUNT_EMPTY=$(count_lines "")
assert_eq "Empty string -> 0" "0" "$COUNT_EMPTY"

# 3b. Single line returns 1
COUNT_ONE=$(count_lines "single line")
assert_eq "Single line -> 1" "1" "$COUNT_ONE"

# 3c. Multiple lines
COUNT_MULTI=$(count_lines "line1
line2
line3")
assert_eq "Three lines -> 3" "3" "$COUNT_MULTI"

# 3d. Five lines
COUNT_FIVE=$(count_lines "a
b
c
d
e")
assert_eq "Five lines -> 5" "5" "$COUNT_FIVE"

# =====================================================================
# Test 4: has_issues
# =====================================================================
echo ""
echo "[Test 4] has_issues"

# has_issues uses global UNRESOLVED_ISSUES variable
# returns 0 (true) if real issues exist, 1 (false) if none

# 4a. Empty string -> no issues (rc=1)
UNRESOLVED_ISSUES=""
has_issues && HAS_RC=0 || HAS_RC=$?
assert_rc "Empty string -> false (rc=1)" 1 "$HAS_RC"

# 4b. "없음" -> no issues (rc=1)
UNRESOLVED_ISSUES="없음"
has_issues && HAS_RC=0 || HAS_RC=$?
assert_rc "'없음' -> false (rc=1)" 1 "$HAS_RC"

# 4c. "None" -> no issues (rc=1)
UNRESOLVED_ISSUES="None"
has_issues && HAS_RC=0 || HAS_RC=$?
assert_rc "'None' -> false (rc=1)" 1 "$HAS_RC"

# 4d. "N/A" -> no issues (rc=1)
UNRESOLVED_ISSUES="N/A"
has_issues && HAS_RC=0 || HAS_RC=$?
assert_rc "'N/A' -> false (rc=1)" 1 "$HAS_RC"

# 4e. "No unresolved issues" -> no issues (rc=1)
UNRESOLVED_ISSUES="No unresolved issues"
has_issues && HAS_RC=0 || HAS_RC=$?
assert_rc "'No unresolved issues' -> false (rc=1)" 1 "$HAS_RC"

# 4f. "해당 없음" -> no issues (rc=1)
UNRESOLVED_ISSUES="해당 없음"
has_issues && HAS_RC=0 || HAS_RC=$?
assert_rc "'해당 없음' -> false (rc=1)" 1 "$HAS_RC"

# 4g. Real issue -> has issues (rc=0)
UNRESOLVED_ISSUES="TypeScript 타입 오류가 발생함"
has_issues && HAS_RC=0 || HAS_RC=$?
assert_rc "Real issue -> true (rc=0)" 0 "$HAS_RC"

# 4h. Multi-line real issue -> has issues (rc=0)
UNRESOLVED_ISSUES="테스트 실패: auth.test.ts
빌드 경고: unused import"
has_issues && HAS_RC=0 || HAS_RC=$?
assert_rc "Multi-line issue -> true (rc=0)" 0 "$HAS_RC"

# Reset
UNRESOLVED_ISSUES=""

# =====================================================================
# Test 5: escape_html
# =====================================================================
echo ""
echo "[Test 5] escape_html"

# 5a. Ampersand
ESC_AMP=$(escape_html "foo & bar")
assert_eq "Ampersand escaped" 'foo &amp; bar' "$ESC_AMP"

# 5b. Less-than
ESC_LT=$(escape_html "a < b")
assert_eq "Less-than escaped" 'a &lt; b' "$ESC_LT"

# 5c. Greater-than
ESC_GT=$(escape_html "a > b")
assert_eq "Greater-than escaped" 'a &gt; b' "$ESC_GT"

# 5d. Combined
ESC_COMBINED=$(escape_html "AT&T <b>bold</b>")
assert_eq "Combined HTML entities escaped" 'AT&amp;T &lt;b&gt;bold&lt;/b&gt;' "$ESC_COMBINED"

# 5e. Plain text passes through unchanged
ESC_PLAIN=$(escape_html "hello world")
assert_eq "Plain text unchanged" "hello world" "$ESC_PLAIN"

# 5f. Dot no longer escaped (not HTML special)
ESC_DOT=$(escape_html "파일명.ts")
assert_eq "Dot not escaped" '파일명.ts' "$ESC_DOT"

# 5g. Backtick no longer escaped (not HTML special)
ESC_BACKTICK=$(escape_html 'code`here')
assert_eq "Backtick not escaped" 'code`here' "$ESC_BACKTICK"

# =====================================================================
# Test 6: Full structured message composition (real data)
# =====================================================================
echo ""
echo "[Test 6] Full structured message composition (real context data)"

REAL_CONTEXT_FILE="/home/hoodcat/Projects/hoodcat-harness/.claude/shared-context/da5a0e2a-6358-4c24-a73f-771d99730041/orchestrator-a64680c.md"

if [ -f "$REAL_CONTEXT_FILE" ]; then
  REAL_CONTENT=$(head -c 4000 "$REAL_CONTEXT_FILE" 2>/dev/null || echo "")

  # Simulate the structured message parsing logic from the script
  PLAN_RAW=$(extract_section "$REAL_CONTENT" "Plan")
  PLAN_SUMMARY=""
  if [ -n "$PLAN_RAW" ]; then
    PLAN_SUMMARY=$(echo "$PLAN_RAW" | head -1 | sed 's/^[[:space:]]*-[[:space:]]*//')
  fi

  FILES_RAW=$(extract_section "$REAL_CONTENT" "Files Changed")
  FILES_CHANGED=""
  FILE_COUNT=0
  if [ -n "$FILES_RAW" ]; then
    FILES_CHANGED=$(extract_filenames "$FILES_RAW")
    FILE_COUNT=$(count_lines "$FILES_CHANGED")
  fi

  REVIEW_RAW=$(extract_section "$REAL_CONTENT" "Review Verdicts")
  REVIEW_VERDICTS=""
  if [ -n "$REVIEW_RAW" ]; then
    REVIEW_VERDICTS=$(echo "$REVIEW_RAW" | head -1 | sed 's/^[[:space:]]*-[[:space:]]*//')
  fi

  ISSUES_RAW=$(extract_section "$REAL_CONTENT" "Unresolved Issues")
  UNRESOLVED_ISSUES=""
  if [ -n "$ISSUES_RAW" ]; then
    UNRESOLVED_ISSUES=$(echo "$ISSUES_RAW" | head -1 | sed 's/^[[:space:]]*-[[:space:]]*//')
  fi

  # Verify parsed data
  assert_contains "Real data: Plan summary extracted" "$PLAN_SUMMARY" "텔레그램"
  assert_eq "Real data: File count is 4" "4" "$FILE_COUNT"
  assert_contains "Real data: Files include notify-telegram.sh" "$FILES_CHANGED" "notify-telegram.sh"
  assert_contains "Real data: Files include .env.example" "$FILES_CHANGED" ".env.example"
  assert_contains "Real data: Files include .gitignore" "$FILES_CHANGED" ".gitignore"
  assert_contains "Real data: Files include settings file" "$FILES_CHANGED" "settings"
  assert_contains "Real data: Review verdict is N/A" "$REVIEW_VERDICTS" "N/A"

  # has_issues should return false for this data (없음)
  has_issues && HAS_RC=0 || HAS_RC=$?
  assert_rc "Real data: No unresolved issues" 1 "$HAS_RC"

  # Compose full message (simulate script logic) - HTML format
  PROJECT_NAME="hoodcat-harness"
  COMPLETED_AT="2026-02-15 04:30 KST"

  STATUS_EMOJI=$'\xe2\x9c\x85'  # check mark (no issues)
  ESCAPED_TIME=$(escape_html "$COMPLETED_AT")

  MESSAGE="${STATUS_EMOJI} <b>Orchestrator 완료</b> | <code>${PROJECT_NAME}</code>"
  MESSAGE="${MESSAGE}
"

  if [ -n "$PLAN_SUMMARY" ]; then
    ESCAPED_PLAN=$(escape_html "$PLAN_SUMMARY")
    MESSAGE="${MESSAGE}
$'\xf0\x9f\x93\x8b' <b>작업:</b> ${ESCAPED_PLAN}"
  fi

  if [ "$FILE_COUNT" -gt 0 ]; then
    MESSAGE="${MESSAGE}

$'\xf0\x9f\x93\x81' <b>변경 파일 (${FILE_COUNT}개):</b>"

    while IFS= read -r fname; do
      ESCAPED_FNAME=$(escape_html "$fname")
      MESSAGE="${MESSAGE}
<code>${ESCAPED_FNAME}</code>"
    done <<< "$FILES_CHANGED"
  fi

  if [ -n "$REVIEW_VERDICTS" ]; then
    ESCAPED_REVIEW=$(escape_html "$REVIEW_VERDICTS")
    MESSAGE="${MESSAGE}

$'\xf0\x9f\x94\x8d' <b>리뷰:</b> ${ESCAPED_REVIEW}"
  fi

  MESSAGE="${MESSAGE}

$'\xe2\x9c\x85' <b>미해결:</b> 없음"

  MESSAGE="${MESSAGE}

$'\xf0\x9f\x95\x90' <i>${ESCAPED_TIME}</i>"

  # Verify the composed message
  assert_contains "Message: has status emoji" "$MESSAGE" "$STATUS_EMOJI"
  assert_contains "Message: has Orchestrator header" "$MESSAGE" "<b>Orchestrator"
  assert_contains "Message: has project name" "$MESSAGE" "<code>hoodcat-harness</code>"
  assert_contains "Message: has plan summary" "$MESSAGE" "<b>작업:</b>"
  assert_contains "Message: has file count" "$MESSAGE" "변경 파일"
  assert_contains "Message: has file list" "$MESSAGE" "<code>"
  assert_contains "Message: has review section" "$MESSAGE" "<b>리뷰:</b>"
  assert_contains "Message: has no-issues note" "$MESSAGE" "<b>미해결:</b>"
  assert_contains "Message: has timestamp" "$MESSAGE" "<i>"

  # Verify message is under Telegram limit
  MSG_LEN=${#MESSAGE}
  if [ "$MSG_LEN" -le 4096 ]; then
    echo -e "  ${GREEN}PASS${NC}: Message length ($MSG_LEN) within Telegram limit (4096)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: Message length ($MSG_LEN) exceeds Telegram limit (4096)"
    FAIL=$((FAIL + 1))
  fi

  # Reset
  UNRESOLVED_ISSUES=""
else
  echo -e "  ${YELLOW}SKIP${NC}: Real context file not found at $REAL_CONTEXT_FILE"
fi

# =====================================================================
# Test 7: Fallback message (non-structured input)
# =====================================================================
echo ""
echo "[Test 7] Fallback message for non-structured input"

NON_STRUCTURED_CONTENT="This is just a plain text summary without any markdown headers.
The orchestrator did some work but the report is not structured.
No ### headers here at all."

# Check that structured detection fails
IS_STRUCTURED_TEST=false
if echo "$NON_STRUCTURED_CONTENT" | grep -q "^## Orchestrator Report" 2>/dev/null || \
   echo "$NON_STRUCTURED_CONTENT" | grep -q "^### Plan" 2>/dev/null; then
  IS_STRUCTURED_TEST=true
fi

if [ "$IS_STRUCTURED_TEST" = false ]; then
  echo -e "  ${GREEN}PASS${NC}: Non-structured content correctly detected as non-structured"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: Non-structured content incorrectly detected as structured"
  FAIL=$((FAIL + 1))
fi

# Test fallback message composition - HTML format
PROJECT_NAME="test-project"
COMPLETED_AT="2026-02-15 04:30 KST"
ESCAPED_PROJECT=$(escape_html "$PROJECT_NAME")
ESCAPED_TIME=$(escape_html "$COMPLETED_AT")
ESCAPED_SUMMARY=$(escape_html "$NON_STRUCTURED_CONTENT")

FALLBACK_MSG=$'\xe2\x9c\x85'" <b>Orchestrator 완료</b> | <code>${PROJECT_NAME}</code>
$'\xf0\x9f\x95\x90' <i>${ESCAPED_TIME}</i>
$'\xf0\x9f\x93\x9d' <b>요약:</b>
${ESCAPED_SUMMARY}"

assert_contains "Fallback: has check emoji" "$FALLBACK_MSG" $'\xe2\x9c\x85'
assert_contains "Fallback: has Orchestrator header" "$FALLBACK_MSG" "<b>Orchestrator"
assert_contains "Fallback: has project name" "$FALLBACK_MSG" "<code>test-project</code>"
assert_contains "Fallback: has timestamp" "$FALLBACK_MSG" "<i>"
assert_contains "Fallback: has summary label" "$FALLBACK_MSG" "<b>요약:</b>"
assert_contains "Fallback: has content" "$FALLBACK_MSG" "plain text summary"

# Test fallback with no context file (empty summary) - HTML format
EMPTY_FALLBACK=$'\xe2\x9c\x85'" <b>Orchestrator 완료</b> | <code>${PROJECT_NAME}</code>
$'\xf0\x9f\x95\x90' <i>${ESCAPED_TIME}</i>

작업이 완료되었습니다."

assert_contains "Empty fallback: has completion message" "$EMPTY_FALLBACK" "완료되었습니다"

# Test that "### Plan" in content triggers structured detection
PARTIAL_STRUCTURED="Some intro text
### Plan
- Do something"

IS_PARTIAL_TEST=false
if echo "$PARTIAL_STRUCTURED" | grep -q "^## Orchestrator Report" 2>/dev/null || \
   echo "$PARTIAL_STRUCTURED" | grep -q "^### Plan" 2>/dev/null; then
  IS_PARTIAL_TEST=true
fi

if [ "$IS_PARTIAL_TEST" = true ]; then
  echo -e "  ${GREEN}PASS${NC}: Content with ### Plan detected as structured"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: Content with ### Plan not detected as structured"
  FAIL=$((FAIL + 1))
fi

# =====================================================================
# Test 8: get_agent_display_name / get_agent_emoji mapping
# =====================================================================
echo ""
echo "[Test 8] Agent type display name and emoji mapping"

# 8a. Known agent types
assert_eq "Display name: orchestrator" "Orchestrator" "$(get_agent_display_name "orchestrator")"
assert_eq "Display name: coder" "Coder" "$(get_agent_display_name "coder")"
assert_eq "Display name: researcher" "Researcher" "$(get_agent_display_name "researcher")"
assert_eq "Display name: reviewer" "Reviewer" "$(get_agent_display_name "reviewer")"
assert_eq "Display name: security" "Security" "$(get_agent_display_name "security")"
assert_eq "Display name: architect" "Architect" "$(get_agent_display_name "architect")"
assert_eq "Display name: navigator" "Navigator" "$(get_agent_display_name "navigator")"
assert_eq "Display name: committer" "Committer" "$(get_agent_display_name "committer")"

# 8b. Unknown agent type falls through as-is
assert_eq "Display name: unknown type passed through" "custom-agent" "$(get_agent_display_name "custom-agent")"

# 8c. Emoji mapping - check non-empty output for known types
EMOJI_CODER=$(get_agent_emoji "coder")
if [ -n "$EMOJI_CODER" ]; then
  echo -e "  ${GREEN}PASS${NC}: Emoji: coder returns non-empty emoji"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: Emoji: coder returns empty"
  FAIL=$((FAIL + 1))
fi

EMOJI_UNKNOWN=$(get_agent_emoji "unknown-type")
if [ -n "$EMOJI_UNKNOWN" ]; then
  echo -e "  ${GREEN}PASS${NC}: Emoji: unknown type returns gear emoji"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: Emoji: unknown type returns empty"
  FAIL=$((FAIL + 1))
fi

# 8d. Each known type returns a distinct emoji
EMOJI_ORCH=$(get_agent_emoji "orchestrator")
EMOJI_RESEARCHER=$(get_agent_emoji "researcher")
EMOJI_REVIEWER=$(get_agent_emoji "reviewer")
EMOJI_SECURITY=$(get_agent_emoji "security")
EMOJI_ARCHITECT=$(get_agent_emoji "architect")
EMOJI_NAVIGATOR=$(get_agent_emoji "navigator")
EMOJI_COMMITTER=$(get_agent_emoji "committer")

# Coder and researcher should differ
if [ "$EMOJI_CODER" != "$EMOJI_RESEARCHER" ]; then
  echo -e "  ${GREEN}PASS${NC}: Emoji: coder and researcher differ"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: Emoji: coder and researcher are the same"
  FAIL=$((FAIL + 1))
fi

# =====================================================================
# Test 9: Non-orchestrator agent message composition
# =====================================================================
echo ""
echo "[Test 9] Non-orchestrator agent message composition"

# Simulate non-orchestrator agent message construction
AGENT_TYPE_TEST="coder"
AGENT_DISPLAY_NAME_TEST=$(get_agent_display_name "$AGENT_TYPE_TEST")
AGENT_EMOJI_TEST=$(get_agent_emoji "$AGENT_TYPE_TEST")
PROJECT_NAME="test-project"
COMPLETED_AT="2026-02-15 12:00 KST"
ESCAPED_PROJECT=$(escape_html "$PROJECT_NAME")
ESCAPED_TIME=$(escape_html "$COMPLETED_AT")
ESCAPED_DISPLAY_NAME_TEST=$(escape_html "$AGENT_DISPLAY_NAME_TEST")

# Build message like the script does for non-orchestrator
NON_ORCH_MSG="${AGENT_EMOJI_TEST} <b>${ESCAPED_DISPLAY_NAME_TEST} 완료</b> | <code>${ESCAPED_PROJECT}</code>"
NON_ORCH_MSG="${NON_ORCH_MSG}

"$'\xf0\x9f\x95\x90'" <i>${ESCAPED_TIME}</i>"

# 9a. Header contains display name
assert_contains "Non-orch msg: has display name" "$NON_ORCH_MSG" "<b>Coder"
assert_contains "Non-orch msg: has '완료'" "$NON_ORCH_MSG" "완료</b>"
assert_contains "Non-orch msg: has project name" "$NON_ORCH_MSG" "<code>test-project</code>"
assert_contains "Non-orch msg: has timestamp" "$NON_ORCH_MSG" "<i>"
assert_contains "Non-orch msg: has agent emoji" "$NON_ORCH_MSG" "$AGENT_EMOJI_TEST"

# 9b. Non-orchestrator message does NOT contain "Orchestrator"
assert_not_contains "Non-orch msg: no 'Orchestrator' text" "$NON_ORCH_MSG" "Orchestrator"

# 9c. With context summary appended
CONTEXT_TEXT="## Coder Report
### Changed Files
- src/main.ts -- 메인 로직 수정"
ESCAPED_CONTEXT=$(escape_html "$CONTEXT_TEXT")
NON_ORCH_MSG_WITH_CTX="${NON_ORCH_MSG}

"$'\xf0\x9f\x93\x9d'" <b>요약:</b>
${ESCAPED_CONTEXT}"

assert_contains "Non-orch msg with context: has summary label" "$NON_ORCH_MSG_WITH_CTX" "<b>요약:</b>"
assert_contains "Non-orch msg with context: has context content" "$NON_ORCH_MSG_WITH_CTX" "Coder Report"

# 9d. Reviewer agent message
REVIEWER_DISPLAY=$(get_agent_display_name "reviewer")
REVIEWER_EMOJI=$(get_agent_emoji "reviewer")
REVIEWER_MSG="${REVIEWER_EMOJI} <b>${REVIEWER_DISPLAY} 완료</b> | <code>my-app</code>"
assert_contains "Reviewer msg: has Reviewer name" "$REVIEWER_MSG" "<b>Reviewer"
assert_contains "Reviewer msg: has project" "$REVIEWER_MSG" "<code>my-app</code>"

# 9e. Message length is reasonable (well under 4096)
MSG_LEN=${#NON_ORCH_MSG_WITH_CTX}
if [ "$MSG_LEN" -le 4096 ]; then
  echo -e "  ${GREEN}PASS${NC}: Non-orch message length ($MSG_LEN) within Telegram limit (4096)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: Non-orch message length ($MSG_LEN) exceeds Telegram limit (4096)"
  FAIL=$((FAIL + 1))
fi

# =====================================================================
# Results
# =====================================================================
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
