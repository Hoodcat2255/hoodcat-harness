#!/usr/bin/env bash
# TaskCompleted Hook - 태스크 완료 전 빌드/테스트 자동 검증
# 에이전트팀의 팀원이 태스크를 완료(TaskUpdate status=completed)할 때 실행된다.
# exit 0 = 완료 허용, exit 2 = 완료 차단 + 피드백 전송
# === OMC 호환 매핑 (Phase 4) ===
# OMC 전환 시: OMC verifier 에이전트 호출로 대체.
# 호출: Agent(subagent_type="oh-my-claudecode:verifier", model="sonnet", prompt="task verification")
# 또는 /oh-my-claudecode:verify 스킬 사용.
# TaskCompleted 자동 트리거가 필요하면 OMC의 동일 이벤트 훅에서 verifier 호출.
# 매핑 신뢰도: 중간 (빌드/테스트 자동 검증 동등성은 verifier prompt에 명시 필요).
# 자세한 사항: docs/migration-omc-mapping-20260522.md 3절.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.claude/log"
LOG_FILE="$LOG_DIR/hooks.log"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")] TASK_QUALITY_GATE: $1" >> "$LOG_FILE"
}

# stdin에서 hook 입력 읽기
input=$(cat)

# jq 미설치 시 안전하게 완료 허용
if ! command -v jq &>/dev/null; then
  log "WARN: jq not installed, allowing task completion"
  exit 0
fi

# 태스크 정보 추출
task_subject=$(echo "$input" | jq -r '.task.subject // ""' 2>/dev/null || echo "")
task_id=$(echo "$input" | jq -r '.task.id // ""' 2>/dev/null || echo "")
agent_name=$(echo "$input" | jq -r '.agent.name // ""' 2>/dev/null || echo "")

log "Task completing: id=$task_id subject='$task_subject' agent=$agent_name"

# 구현/개발 관련 태스크인 경우에만 빌드/테스트 검증
if echo "$task_subject" | grep -qiE '구현|implement|개발|develop|코드|code|build|빌드'; then
  log "Implementation task detected, running verification"

  if [ -f "$PROJECT_DIR/.claude/hooks/verify-build-test.sh" ]; then
    result=$("$PROJECT_DIR/.claude/hooks/verify-build-test.sh" "$PROJECT_DIR" 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
      log "BLOCK: Build/test verification failed for task=$task_id"
      echo "빌드/테스트 검증 실패. 태스크 완료를 차단합니다. 오류를 수정한 후 다시 완료 처리하세요: $result"
      exit 2  # exit 2 = 완료 차단 + 피드백 전송
    else
      log "PASS: Build/test verification passed for task=$task_id"
    fi
  else
    log "INFO: verify-build-test.sh not found, skipping verification"
  fi
else
  log "INFO: Non-implementation task, skipping verification"
fi

exit 0
