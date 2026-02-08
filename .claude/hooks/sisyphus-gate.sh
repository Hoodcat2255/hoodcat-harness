#!/usr/bin/env bash
# Sisyphus Gate - Stop Hook for non-stop workflow enforcement
# 워크플로우 스킬이 모든 Phase를 완료할 때까지 종료를 차단한다.
# active=false일 때는 일반 작업에 영향을 주지 않는다.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FLAGS_FILE="$PROJECT_DIR/.claude/flags/sisyphus.json"
LOG_DIR="$PROJECT_DIR/.claude/log"
LOG_FILE="$LOG_DIR/sisyphus.log"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

# stdin에서 hook 입력 읽기
HOOK_INPUT=$(cat)

# jq 미설치 시 안전하게 종료 허용
if ! command -v jq &>/dev/null; then
  log "WARN: jq not installed, allowing stop"
  exit 0
fi

# flags 파일 없으면 종료 허용
if [ ! -f "$FLAGS_FILE" ]; then
  log "INFO: no flags file, allowing stop"
  exit 0
fi

# active 상태 확인
ACTIVE=$(jq -r '.active' "$FLAGS_FILE" 2>/dev/null || echo "false")

if [ "$ACTIVE" != "true" ]; then
  log "INFO: sisyphus inactive, allowing stop"
  exit 0
fi

# active=true → iteration 카운터 증가
CURRENT=$(jq -r '.currentIteration' "$FLAGS_FILE" 2>/dev/null || echo "0")
MAX=$(jq -r '.maxIterations' "$FLAGS_FILE" 2>/dev/null || echo "15")
WORKFLOW=$(jq -r '.workflow' "$FLAGS_FILE" 2>/dev/null || echo "unknown")
PHASE=$(jq -r '.phase' "$FLAGS_FILE" 2>/dev/null || echo "unknown")

NEXT=$((CURRENT + 1))

# iteration 카운터 업데이트
jq --argjson next "$NEXT" '.currentIteration=$next' "$FLAGS_FILE" > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp "$FLAGS_FILE"

# maxIterations 도달 → 안전장치: 강제 종료
if [ "$NEXT" -ge "$MAX" ]; then
  log "SAFETY: max iterations ($MAX) reached for workflow=$WORKFLOW phase=$PHASE. Deactivating and allowing stop."
  jq '.active=false | .phase="safety-stopped"' "$FLAGS_FILE" > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp "$FLAGS_FILE"
  exit 0
fi

# 아직 미도달 → 종료 차단
REASON="[Sisyphus] 워크플로우 '$WORKFLOW' 진행 중 (phase=$PHASE, iteration=$NEXT/$MAX). 모든 Phase를 완료할 때까지 멈추지 마세요. 다음 Phase로 진행하세요."
log "BLOCK: workflow=$WORKFLOW phase=$PHASE iteration=$NEXT/$MAX"

echo "{\"decision\": \"block\", \"reason\": \"$REASON\"}"
exit 0
