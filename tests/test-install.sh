#!/usr/bin/env bash
# install.sh / uninstall.sh 통합 테스트.
# 임시 CLAUDE_CONFIG_DIR·HOODCAT_BIN_DIR에서 --skip-omc로 실행하므로 실제 ~/.claude는 건드리지 않는다.
# 사용법: bash tests/test-install.sh   (exit 0 = 전부 통과)

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

export CLAUDE_CONFIG_DIR="${SANDBOX}/claude"
export HOODCAT_BIN_DIR="${SANDBOX}/bin"
mkdir -p "$CLAUDE_CONFIG_DIR/skills/my-own-skill"
echo "user skill" > "$CLAUDE_CONFIG_DIR/skills/my-own-skill/SKILL.md"

# 사용자가 원래 가지고 있던 settings.json (다른 훅·설정 보존 확인용)
cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'EOF'
{
  "model": "opus",
  "hooks": {
    "SubagentStop": [ { "hooks": [ { "type": "command", "command": "/usr/local/bin/other-hook.sh" } ] } ],
    "PreToolUse":   [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "/usr/local/bin/guard.sh" } ] } ]
  }
}
EOF
ORIGINAL_SETTINGS="$(jq -S . "$CLAUDE_CONFIG_DIR/settings.json")"

PASS=0; FAIL=0
check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ✓ $desc"
    else FAIL=$((FAIL+1)); echo "  ✗ $desc"; fi
}

DR_HOOK="${CLAUDE_CONFIG_DIR}/hooks/hoodcat/dr-prefix.sh"
MANIFEST="${CLAUDE_CONFIG_DIR}/.hoodcat-pack.json"
# 사용법: count_hook <이벤트> <명령 경로>
count_hook() { jq --arg e "$1" --arg c "$2" '[.hooks[$e][]?.hooks[]? | select(.command == $c)] | length' "$CLAUDE_CONFIG_DIR/settings.json"; }

echo "[1] dry-run은 아무것도 바꾸지 않는다"
"$REPO_DIR/install.sh" --skip-omc --dry-run >/dev/null
check "매니페스트 없음" test ! -e "$MANIFEST"
check "settings.json 그대로" test "$(jq -S . "$CLAUDE_CONFIG_DIR/settings.json")" = "$ORIGINAL_SETTINGS"

echo "[2] 설치"
"$REPO_DIR/install.sh" --skip-omc >/dev/null
check "스킬 설치" test -f "$CLAUDE_CONFIG_DIR/skills/deepresearch/SKILL.md"
check "규칙 설치" test -f "$CLAUDE_CONFIG_DIR/rules/hoodcat/source-hierarchy.md"
check "dr-prefix 훅 실행 권한" test -x "$DR_HOOK"
check "dr-prefix 훅 등록 1회 (UserPromptSubmit)" test "$(count_hook UserPromptSubmit "$DR_HOOK")" = 1
check "기존 훅 보존" jq -e '.hooks.PreToolUse[0].hooks[0].command == "/usr/local/bin/guard.sh"' "$CLAUDE_CONFIG_DIR/settings.json"
check "기존 설정 보존" jq -e '.model == "opus"' "$CLAUDE_CONFIG_DIR/settings.json"
check "사용자 스킬 보존" test -f "$CLAUDE_CONFIG_DIR/skills/my-own-skill/SKILL.md"
check "매니페스트 기록" jq -e '(.paths | length) > 0 and (.hooks | length) == 1' "$MANIFEST"

echo "[3] 재설치는 중복 없이 동기화"
"$REPO_DIR/install.sh" --skip-omc >/dev/null
check "dr-prefix 훅 등록 여전히 1회" test "$(count_hook UserPromptSubmit "$DR_HOOK")" = 1
check "백업 디렉토리 없음 (내 파일은 백업 대상 아님)" test ! -d "$CLAUDE_CONFIG_DIR/.hoodcat-pack-backup"

echo "[4] 제거하면 원래 상태로"
"$REPO_DIR/uninstall.sh" >/dev/null
check "스킬 제거" test ! -e "$CLAUDE_CONFIG_DIR/skills/deepresearch"
check "규칙 네임스페이스 제거" test ! -e "$CLAUDE_CONFIG_DIR/rules/hoodcat"
check "훅 네임스페이스 제거" test ! -e "$CLAUDE_CONFIG_DIR/hooks/hoodcat"
check "매니페스트 제거" test ! -e "$MANIFEST"
check "settings.json 원상 복구" test "$(jq -S . "$CLAUDE_CONFIG_DIR/settings.json")" = "$ORIGINAL_SETTINGS"
check "사용자 스킬 보존" test -f "$CLAUDE_CONFIG_DIR/skills/my-own-skill/SKILL.md"

echo "[5] 내 것이 아닌 기존 파일과 충돌하면 백업 후 덮어쓴다"
mkdir -p "$CLAUDE_CONFIG_DIR/skills/deepresearch"
echo "someone else's" > "$CLAUDE_CONFIG_DIR/skills/deepresearch/SKILL.md"
"$REPO_DIR/install.sh" --skip-omc >/dev/null 2>&1
check "백업 생성" bash -c "grep -rq \"someone else's\" '$CLAUDE_CONFIG_DIR/.hoodcat-pack-backup'"
check "새 스킬로 교체" grep -q 'Deep Research' "$CLAUDE_CONFIG_DIR/skills/deepresearch/SKILL.md"
"$REPO_DIR/uninstall.sh" >/dev/null

echo "[6] 매니페스트 없이 제거하면 아무 일도 없다"
check "exit 0" "$REPO_DIR/uninstall.sh"

echo
echo "통과 ${PASS} / 실패 ${FAIL}"
[[ "$FAIL" -eq 0 ]]
