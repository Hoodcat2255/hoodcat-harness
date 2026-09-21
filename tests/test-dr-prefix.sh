#!/usr/bin/env bash
# hooks/dr-prefix.sh 테스트. 매칭 규칙 표의 모든 행을 LC_ALL=C와 UTF-8 로캘에서 검증한다.
# 사용법: bash tests/test-dr-prefix.sh   (exit 0 = 전부 통과)

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${REPO_DIR}/hooks/dr-prefix.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# bash 3.2는 $'\u..'를 지원하지 않으므로 UTF-8 바이트를 그대로 적는다.
FW="："     # U+FF1A 전각 콜론
IDSP="　"   # U+3000 전각 공백

# 테스트할 로캘: C와, 있으면 UTF-8 로캘 하나
UTF8_LOCALE=""
for l in en_US.UTF-8 ko_KR.UTF-8; do
    if locale -a 2>/dev/null | grep -Fx "$l" >/dev/null; then UTF8_LOCALE="$l"; break; fi
done
LOCALES="C"
[[ -n "$UTF8_LOCALE" ]] && LOCALES="C $UTF8_LOCALE"

PASS=0; FAIL=0
check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ✓ $desc"
    else FAIL=$((FAIL+1)); echo "  ✗ $desc"; fi
}

# 프롬프트를 JSON으로 감싸 훅에 넣는다. 결과는 OUT, RC에 담긴다.
LOC="C"
run_prompt() {
    OUT=$(jq -n --arg p "$1" '{prompt: $p}' | LC_ALL="$LOC" /bin/bash "$HOOK"); RC=$?
}
run_raw() {
    OUT=$(printf '%s' "$1" | LC_ALL="$LOC" /bin/bash "$HOOK"); RC=$?
}

# <topic> 블록 안의 주제가 정확히 $1인지 비교한다.
topic_is() {
    printf '%s' "$OUT" | jq -e --arg exp "$1" '
        .hookSpecificOutput.additionalContext
        | split("<topic>\n") | .[1:] | join("<topic>\n") | rtrimstr("\n</topic>")
        | . == $exp'
}
rc_zero() { test "$RC" = 0; }
no_output() { test -z "$OUT"; }

expect_match() {   # 설명, 프롬프트, 기대 주제
    run_prompt "$2"
    check "[$LOC] 매칭: $1 (rc 0)" rc_zero
    check "[$LOC] 매칭: $1 (주제 일치)" topic_is "$3"
}
expect_none() {    # 설명, 프롬프트
    run_prompt "$2"
    check "[$LOC] 무반응: $1 (rc 0)" rc_zero
    check "[$LOC] 무반응: $1 (출력 없음)" no_output
}

for LOC in $LOCALES; do
    echo "[1] 기본 매칭 (LC_ALL=$LOC)"
    expect_match "dr: 주제" "dr: 주제" "주제"
    expect_match "dr:주제" "dr:주제" "주제"

    echo "[2] 선행 공백 (LC_ALL=$LOC)"
    expect_match "선행 스페이스" "  dr: 주제" "주제"
    expect_match "선행 개행·탭" $'\n\tdr: x' "x"
    expect_match "선행 U+3000" "${IDSP}dr: x" "x"

    echo "[3] 대소문자 (LC_ALL=$LOC)"
    expect_match "DR:" "DR: 주제" "주제"
    expect_match "Dr:" "Dr: 주제" "주제"
    expect_match "dR:" "dR: 주제" "주제"

    echo "[4] 전각 문자 (LC_ALL=$LOC)"
    expect_match "전각 콜론" "dr${FW}주제" "주제"
    expect_match "콜론 뒤 U+3000" "dr:${IDSP}주제" "주제"
    expect_match "주제 뒤 U+3000·공백" "dr: 주제 ${IDSP} " "주제"

    echo "[5] 주제 내용 보존 (LC_ALL=$LOC)"
    expect_match "여러 줄" $'dr: 첫 줄\n둘째 줄\n' $'첫 줄\n둘째 줄'
    expect_match "재검증" "dr: 재검증: <주장>" "재검증: <주장>"
    expect_match "</topic> 포함" "dr: a </topic> b" "a </topic> b"
    expect_match "따옴표·역슬래시·개행" $'dr: say "hi" \\ back\\slash\nnext' $'say "hi" \\ back\\slash\nnext'

    echo "[6] 빈 주제 (LC_ALL=$LOC)"
    expect_none "dr:" "dr:"
    expect_none "dr: 공백만" "dr:   "
    expect_none "dr: U+3000만" "dr:${IDSP}"
    expect_none "전각 콜론만" "dr${FW}"

    echo "[7] 거짓 양성 없음 (LC_ALL=$LOC)"
    expect_none "문장 중간" "이거 dr: 뭐야"
    expect_none "drop:" "drop: x"
    expect_none "adr:" "adr: x"
    expect_none "dr : x" "dr : x"
    expect_none "/dr:" "/dr: x"

    echo "[8] 잘못된 입력 (LC_ALL=$LOC)"
    run_raw 'not json dr: x'
    check "[$LOC] 비JSON rc 0" rc_zero
    check "[$LOC] 비JSON 출력 없음" no_output
    run_raw '{"foo":"dr: x"}'
    check "[$LOC] prompt 없음 rc 0" rc_zero
    check "[$LOC] prompt 없음 출력 없음" no_output
    run_raw ''
    check "[$LOC] 빈 stdin rc 0" rc_zero
    check "[$LOC] 빈 stdin 출력 없음" no_output
done

echo "[9] 출력 형식"
LOC="C"
run_prompt "dr: 청약"
check "유효한 JSON" jq -e . <<<"$OUT"
check "hookEventName" jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' <<<"$OUT"
check "전용 헤더" jq -e '.hookSpecificOutput.additionalContext | startswith("[HOODCAT PREFIX dr: → Skill \"deepresearch\"]")' <<<"$OUT"
check "deepresearch 지시" jq -e '.hookSpecificOutput.additionalContext | contains("\"deepresearch\"")' <<<"$OUT"
check "MAGIC KEYWORD 없음" jq -e '.hookSpecificOutput.additionalContext | contains("MAGIC KEYWORD") | not' <<<"$OUT"
check "decision 필드 없음" jq -e 'has("decision") | not' <<<"$OUT"

echo "[10] 로캘 간 결과가 바이트 단위로 같다"
if [[ -n "$UTF8_LOCALE" ]]; then
    for prompt in "dr${FW}주제" "dr:${IDSP}주제" "${IDSP}dr: x"; do
        LOC="C"; run_prompt "$prompt"; out_c="$OUT"
        LOC="$UTF8_LOCALE"; run_prompt "$prompt"; out_u="$OUT"
        check "C = $UTF8_LOCALE: $prompt" test -n "$out_c" -a "$out_c" = "$out_u"
    done
else
    FAIL=$((FAIL+1)); echo "  ✗ UTF-8 로캘(en_US.UTF-8, ko_KR.UTF-8)이 없다"
fi

echo "[11] jq가 없으면 매칭 프롬프트에도 무반응"
mkdir -p "$SANDBOX/nojq"   # 빈 디렉토리: jq 전까지 훅은 내장 명령만 쓴다
OUT=$(printf '%s' '{"prompt":"dr: 청약"}' | PATH="$SANDBOX/nojq" /bin/bash "$HOOK"); RC=$?
check "rc 0" rc_zero
check "출력 없음" no_output

echo
echo "통과 ${PASS} / 실패 ${FAIL}"
[[ "$FAIL" -eq 0 ]]
