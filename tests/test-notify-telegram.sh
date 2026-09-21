#!/usr/bin/env bash
# hooks/notify-telegram.sh 테스트. curl을 가짜로 바꿔 전송 인자를 파일로 받는다.
# 사용법: bash tests/test-notify-telegram.sh   (exit 0 = 전부 통과)

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${REPO_DIR}/hooks/notify-telegram.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

mkdir -p "$SANDBOX/bin" "$SANDBOX/claude" "$SANDBOX/proj"
CAPTURE="$SANDBOX/curl-args"
cat > "$SANDBOX/bin/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$CAPTURE"
EOF
chmod +x "$SANDBOX/bin/curl"

export PATH="$SANDBOX/bin:$PATH"
export CLAUDE_CONFIG_DIR="$SANDBOX/claude"
unset HARNESS_TG_BOT_TOKEN HARNESS_TG_CHAT_ID

PASS=0; FAIL=0
check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ✓ $desc"
    else FAIL=$((FAIL+1)); echo "  ✗ $desc"; fi
}

payload() {
    jq -n --arg cwd "$SANDBOX/proj" --arg msg "$1" \
        '{cwd: $cwd, agent_type: "oh-my-claudecode:executor", last_assistant_message: $msg}'
}

# 백그라운드 curl이 끝날 때까지 잠깐 기다린다.
run_hook() { rm -f "$CAPTURE"; payload "$1" | bash "$HOOK"; local rc=$?; for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -f "$CAPTURE" ]] && break; sleep 0.1; done; return $rc; }

echo "[1] 토큰이 없으면 보내지 않고 exit 0"
run_hook "hi"; rc=$?
check "exit 0" test "$rc" = 0
check "curl 호출 없음" test ! -f "$CAPTURE"

echo "[2] 전역 .env의 토큰으로 전송"
printf 'HARNESS_TG_BOT_TOKEN="TOKEN123"\nHARNESS_TG_CHAT_ID=42\nOTHER_SECRET=nope\n' > "$SANDBOX/claude/.env"
run_hook '## 결과
**완료** `a<b` & done'
check "API URL에 토큰" grep -q 'bot TOKEN123/sendMessage\|botTOKEN123/sendMessage' "$CAPTURE"
check "chat_id 전달" grep -q '^chat_id=42$' "$CAPTURE"
check "프로젝트명 포함" grep -q '<code>proj</code>' "$CAPTURE"
check "에이전트명 포함" grep -q 'oh-my-claudecode:executor 완료' "$CAPTURE"
check "마크다운 제거" bash -c "! grep -q '\*\*' '$CAPTURE'"
check "HTML 이스케이프" grep -q 'a&lt;b &amp; done' "$CAPTURE"

echo "[3] 프로젝트 .env가 전역을 덮어쓴다"
printf 'HARNESS_TG_CHAT_ID=99\n' > "$SANDBOX/proj/.env"
run_hook "x"
check "chat_id 덮어쓰기" grep -q '^chat_id=99$' "$CAPTURE"

echo "[4] 잘못된 입력에도 exit 0"
echo 'not json' | bash "$HOOK"; rc=$?
check "exit 0" test "$rc" = 0

echo
echo "통과 ${PASS} / 실패 ${FAIL}"
[[ "$FAIL" -eq 0 ]]
