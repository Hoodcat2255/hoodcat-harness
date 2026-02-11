#!/usr/bin/env bash
# TeammateIdle Hook - 팀원이 유휴 상태로 전환될 때 실행
# 미완료 태스크가 남아있는 팀원이 유휴 상태가 되면 작업 재개를 유도한다.
# exit 0 = 유휴 허용, exit 2 = 피드백 전송 + 작업 계속

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.claude/log"
LOG_FILE="$LOG_DIR/hooks.log"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date -Iseconds)] TEAMMATE_IDLE: $1" >> "$LOG_FILE"
}

# stdin에서 hook 입력 읽기
input=$(cat)

# jq 미설치 시 안전하게 유휴 허용
if ! command -v jq &>/dev/null; then
  log "WARN: jq not installed, allowing idle"
  exit 0
fi

# 팀원 정보 추출
agent_name=$(echo "$input" | jq -r '.agent.name // ""' 2>/dev/null || echo "")
team_name=$(echo "$input" | jq -r '.team.name // ""' 2>/dev/null || echo "")

log "Teammate idle: agent=$agent_name team=$team_name"

# 팀 태스크 디렉토리 확인
TASKS_DIR="$HOME/.claude/tasks/$team_name"
if [ -z "$team_name" ] || [ ! -d "$TASKS_DIR" ]; then
  log "INFO: No team tasks directory found for team=$team_name, allowing idle"
  exit 0
fi

# 해당 팀원에게 할당된 미완료 태스크가 있는지 확인
pending_tasks=0
for task_file in "$TASKS_DIR"/*.json; do
  [ -f "$task_file" ] || continue
  owner=$(jq -r '.owner // ""' "$task_file" 2>/dev/null || echo "")
  status=$(jq -r '.status // ""' "$task_file" 2>/dev/null || echo "")

  if [ "$owner" = "$agent_name" ] && [ "$status" = "in_progress" ]; then
    pending_tasks=$((pending_tasks + 1))
  fi
done

if [ "$pending_tasks" -gt 0 ]; then
  log "NUDGE: agent=$agent_name has $pending_tasks in-progress tasks, sending feedback"
  echo "아직 진행 중인 태스크가 ${pending_tasks}개 있습니다. TaskList를 확인하고 할당된 태스크를 완료해 주세요."
  exit 2  # exit 2 = 피드백 전송 + 작업 계속
fi

log "INFO: agent=$agent_name has no in-progress tasks, allowing idle"
exit 0
