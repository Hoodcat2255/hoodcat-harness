#!/usr/bin/env bash
# UserPromptSubmit Hook - dr-prefix.sh
# 프롬프트가 `dr:`(대소문자 무관, 전각 콜론 `：` 포함)로 시작하면 나머지 텍스트를 주제로
# deepresearch 스킬을 호출하라는 지시를 additionalContext로 주입한다.
# 입력(stdin JSON): prompt (Claude Code hooks 문서 UserPromptSubmit 절)
# 프롬프트를 막거나 바꾸지 않는다. 호출 자체는 모델이 지시를 따라 수행한다.
# 이식성: macOS /bin/bash 3.2, LC_ALL=C에서도 동작한다 (오프셋 슬라이스를 쓰지 않는다).
# 안전성: 어떤 경우에도 exit 0 (세션을 막지 않는다).

set -uo pipefail

IFS= read -r -d '' INPUT || true

# 빠른 경로: `dr:` 문자열이 없으면 jq 없이 바로 끝낸다.
case "$INPUT" in *[Dd][Rr]:*|*[Dd][Rr]：*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0

p=$(jq -r '.prompt // empty' <<<"$INPUT" 2>/dev/null) || exit 0

# 선행 공백(`[[:space:]]`와 전각 공백 U+3000) 제거
while :; do
    case "$p" in
        [[:space:]]*) p=${p#[[:space:]]} ;;
        　*) p=${p#　} ;;
        *) break ;;
    esac
done

# 접두어 판정과 주제 추출 (패턴 제거만 쓴다)
case "$p" in
    [Dd][Rr]:*) t=${p#[Dd][Rr]:} ;;
    [Dd][Rr]：*) t=${p#[Dd][Rr]：} ;;
    *) exit 0 ;;
esac

# 주제 앞뒤 trim (`[[:space:]]`와 U+3000)
while :; do
    case "$t" in
        [[:space:]]*) t=${t#[[:space:]]} ;;
        　*) t=${t#　} ;;
        *[[:space:]]) t=${t%[[:space:]]} ;;
        *　) t=${t%　} ;;
        *) break ;;
    esac
done
[[ -n "$t" ]] || exit 0

jq -n --arg topic "$t" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: ("[HOODCAT PREFIX dr: → Skill \"deepresearch\"]\n"
      + "The user started the prompt with the `dr:` prefix. Invoke the Skill tool with skill \"deepresearch\"\n"
      + "(the unscoped user skill — NOT an oh-my-claudecode skill, NOT OMC \"research\") and pass the topic below as args.\n"
      + "Do not answer before invoking the skill. The skill runs in a forked context that cannot see this\n"
      + "conversation: if the topic refers to earlier turns (e.g. \"재검증: 직전 답변\"), inline the referenced\n"
      + "claim text into args. After the skill returns, present its result to the user.\n"
      + "<topic>\n" + $topic + "\n</topic>")
  }
}' 2>/dev/null

exit 0
