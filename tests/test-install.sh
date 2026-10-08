#!/usr/bin/env bash
# install.sh / uninstall.sh 통합 테스트.
# 임시 CLAUDE_CONFIG_DIR·HOODCAT_BIN_DIR·HOODCAT_WHISPER_DIR에서 --skip-omc --skip-whisper-deps로 실행하므로
# 실제 ~/.claude·~/Projects/whisper와 brew·uv는 건드리지 않는다.
# 사용법: bash tests/test-install.sh   (exit 0 = 전부 통과)

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

export CLAUDE_CONFIG_DIR="${SANDBOX}/claude"
export HOODCAT_BIN_DIR="${SANDBOX}/bin"
export HOODCAT_WHISPER_DIR="${SANDBOX}/whisper"
INSTALL="$REPO_DIR/install.sh --skip-omc --skip-whisper-deps"
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
WD="$HOODCAT_WHISPER_DIR"
YT_SKILL="${CLAUDE_CONFIG_DIR}/skills/youtube-digest/SKILL.md"
REC_SKILL="${CLAUDE_CONFIG_DIR}/skills/recording-notes/SKILL.md"
MANIFEST="${CLAUDE_CONFIG_DIR}/.hoodcat-pack.json"
# 사용법: count_hook <이벤트> <명령 경로>
count_hook() { jq --arg e "$1" --arg c "$2" '[.hooks[$e][]?.hooks[]? | select(.command == $c)] | length' "$CLAUDE_CONFIG_DIR/settings.json"; }

echo "[1] dry-run은 아무것도 바꾸지 않는다"
$INSTALL --dry-run >/dev/null
check "매니페스트 없음" test ! -e "$MANIFEST"
check "settings.json 그대로" test "$(jq -S . "$CLAUDE_CONFIG_DIR/settings.json")" = "$ORIGINAL_SETTINGS"
check "전사 파이프라인 디렉토리 없음" test ! -e "$WD"

echo "[2] 설치"
$INSTALL >/dev/null
check "스킬 설치" test -f "$CLAUDE_CONFIG_DIR/skills/deepresearch/SKILL.md"
check "규칙 설치" test -f "$CLAUDE_CONFIG_DIR/rules/hoodcat/source-hierarchy.md"
check "dr-prefix 훅 실행 권한" test -x "$DR_HOOK"
check "dr-prefix 훅 등록 1회 (UserPromptSubmit)" test "$(count_hook UserPromptSubmit "$DR_HOOK")" = 1
check "기존 훅 보존" jq -e '.hooks.PreToolUse[0].hooks[0].command == "/usr/local/bin/guard.sh"' "$CLAUDE_CONFIG_DIR/settings.json"
check "기존 설정 보존" jq -e '.model == "opus"' "$CLAUDE_CONFIG_DIR/settings.json"
check "사용자 스킬 보존" test -f "$CLAUDE_CONFIG_DIR/skills/my-own-skill/SKILL.md"
check "매니페스트 기록" jq -e '(.paths | length) > 0 and (.hooks | length) == 1' "$MANIFEST"
check "전사 파이프라인 동기화" test -f "$WD/transcribe.py" -a -f "$WD/ytscribe/asr.py" -a -f "$WD/uv.lock"
check "매니페스트에 파이프라인 경로" jq -e --arg w "$WD" '.whisper_dir == $w' "$MANIFEST"
check "youtube-digest 스킬 설치" test -f "$YT_SKILL"
check "recording-notes 스킬 설치" test -f "$REC_SKILL"
check "스킬 경로를 HOODCAT_WHISPER_DIR로 치환 (cd는 따옴표)" grep -qF "cd \"$WD\" && uv run" "$YT_SKILL"
check "기본 경로 흔적 없음 (youtube-digest)" bash -c "! grep -q '~/Projects/whisper' '$YT_SKILL'"
check "기본 경로 흔적 없음 (recording-notes)" bash -c "! grep -q '~/Projects/whisper' '$REC_SKILL'"

echo "[3] 재설치는 중복 없이 동기화"
mkdir -p "$WD/output/abc" "$WD/.venv"
echo "전사 결과" > "$WD/output/abc/transcript.md"
echo "venv" > "$WD/.venv/marker"
echo "old" > "$WD/removed_module.py"
mkdir -p "$WD/.claude" "$WD/.git"
echo '{}' > "$WD/.claude/settings.local.json"; echo "ref" > "$WD/.git/HEAD"
echo "secret" > "$WD/.env"; echo "# notes" > "$WD/CLAUDE.md"
$INSTALL >/dev/null
check "dr-prefix 훅 등록 여전히 1회" test "$(count_hook UserPromptSubmit "$DR_HOOK")" = 1
check "백업 디렉토리 없음 (내 파일은 백업 대상 아님)" test ! -d "$CLAUDE_CONFIG_DIR/.hoodcat-pack-backup"
check "전사 결과(output/) 보존" grep -q "전사 결과" "$WD/output/abc/transcript.md"
check ".venv 보존" test -f "$WD/.venv/marker"
check "저장소에서 사라진 파일은 정리" test ! -e "$WD/removed_module.py"
check "설치본의 개인 파일 보존 (.claude .git .env CLAUDE.md)" test -f "$WD/.claude/settings.local.json" -a -f "$WD/.git/HEAD" -a -f "$WD/.env" -a -f "$WD/CLAUDE.md"

echo "[4] 제거하면 원래 상태로"
"$REPO_DIR/uninstall.sh" >/dev/null
check "스킬 제거" test ! -e "$CLAUDE_CONFIG_DIR/skills/deepresearch"
check "규칙 네임스페이스 제거" test ! -e "$CLAUDE_CONFIG_DIR/rules/hoodcat"
check "훅 네임스페이스 제거" test ! -e "$CLAUDE_CONFIG_DIR/hooks/hoodcat"
check "매니페스트 제거" test ! -e "$MANIFEST"
check "settings.json 원상 복구" test "$(jq -S . "$CLAUDE_CONFIG_DIR/settings.json")" = "$ORIGINAL_SETTINGS"
check "사용자 스킬 보존" test -f "$CLAUDE_CONFIG_DIR/skills/my-own-skill/SKILL.md"
check "전사 스킬 제거" test ! -e "$CLAUDE_CONFIG_DIR/skills/youtube-digest" -a ! -e "$CLAUDE_CONFIG_DIR/skills/recording-notes"
check "전사 파이프라인과 결과는 남김" test -f "$WD/transcribe.py" -a -f "$WD/output/abc/transcript.md"

echo "[5] 내 것이 아닌 기존 파일과 충돌하면 백업 후 덮어쓴다"
mkdir -p "$CLAUDE_CONFIG_DIR/skills/deepresearch"
echo "someone else's" > "$CLAUDE_CONFIG_DIR/skills/deepresearch/SKILL.md"
$INSTALL >/dev/null 2>&1
check "백업 생성" bash -c "grep -rq \"someone else's\" '$CLAUDE_CONFIG_DIR/.hoodcat-pack-backup'"
check "새 스킬로 교체" grep -q 'Deep Research' "$CLAUDE_CONFIG_DIR/skills/deepresearch/SKILL.md"
"$REPO_DIR/uninstall.sh" >/dev/null

echo "[6] 매니페스트 없이 제거하면 아무 일도 없다"
check "exit 0" "$REPO_DIR/uninstall.sh"

echo "[7] whisper 사본이 아닌 기존 디렉토리는 건드리지 않는다"
FOREIGN="${SANDBOX}/foreign"
mkdir -p "$FOREIGN"; echo "mine" > "$FOREIGN/notes.txt"
HOODCAT_WHISPER_DIR="$FOREIGN" $INSTALL >/dev/null 2>&1
check "exit 0" test $? -eq 0
check "기존 파일 보존" grep -q mine "$FOREIGN/notes.txt"
check "코드 동기화 안 함" test ! -e "$FOREIGN/transcribe.py"
check "매니페스트에 파이프라인 경로 없음" jq -e 'has("whisper_dir") | not' "$MANIFEST"
"$REPO_DIR/uninstall.sh" >/dev/null

echo "[8] --skip-whisper는 파이프라인 단계를 생략한다"
SKIPPED="${SANDBOX}/skipped"
HOODCAT_WHISPER_DIR="$SKIPPED" $INSTALL --skip-whisper >/dev/null
check "파이프라인 디렉토리 없음" test ! -e "$SKIPPED"
check "스킬은 설치" test -f "$YT_SKILL"
"$REPO_DIR/uninstall.sh" >/dev/null

echo "[9] 의존성 설치·uv sync가 실패해도 설치는 끝나고 매니페스트가 남는다"
STUB="${SANDBOX}/stub"; mkdir -p "$STUB" "${SANDBOX}/home"
for c in uv npx brew; do printf '#!/bin/sh\nexit 1\n' > "$STUB/$c"; chmod +x "$STUB/$c"; done
printf '#!/bin/sh\nexit 0\n' > "$STUB/ffmpeg"; chmod +x "$STUB/ffmpeg"
DEPS_OUT="$(HOME="${SANDBOX}/home" PATH="$STUB:$PATH" HOODCAT_WHISPER_DIR="${SANDBOX}/deps" \
    "$REPO_DIR/install.sh" --skip-omc 2>&1)"
check "exit 0" test $? -eq 0
check "uv sync 실패 경고" bash -c "printf '%s' \"\$1\" | grep -q 'uv sync 실패'" _ "$DEPS_OUT"
check "매니페스트에 스킬과 파이프라인 기록" jq -e --arg w "${SANDBOX}/deps" '.whisper_dir == $w and any(.paths[]; endswith("/youtube-digest"))' "$MANIFEST"
"$REPO_DIR/uninstall.sh" >/dev/null

echo
echo "통과 ${PASS} / 실패 ${FAIL}"
[[ "$FAIL" -eq 0 ]]
