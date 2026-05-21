#!/usr/bin/env bash
# Build & Test Verifier - 프로젝트 언어를 감지하고 빌드/테스트를 실행한다.
# 워크플로우 스킬 내부에서 Bash로 호출한다.
# exit 0 = 성공, exit 1 = 실패
# === OMC 호환 매핑 (Phase 4) ===
# OMC 전환 시: OMC verifier 에이전트 또는 /oh-my-claudecode:verify 스킬로 대체.
# 호출: Agent(subagent_type="oh-my-claudecode:verifier", model="sonnet", prompt="build & test verification")
# 또는 사용자 명령으로 /oh-my-claudecode:verify 직접 실행.
# 프로젝트별 빌드/테스트 명령 자동 감지는 verifier가 동등 기능 제공.
# 매핑 신뢰도: 중간.
# 자세한 사항: docs/migration-omc-mapping-20260522.md 3절.

set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

log() {
  echo "[verify] $1"
}

run_cmd() {
  log "Running: $1"
  if eval "$1"; then
    log "PASS: $1"
    return 0
  else
    log "FAIL: $1"
    return 1
  fi
}

RESULT=0

# Node.js (package.json)
if [ -f "package.json" ]; then
  log "Detected: Node.js project"
  if command -v npm &>/dev/null; then
    if jq -e '.scripts.build' package.json &>/dev/null; then
      run_cmd "npm run build" || RESULT=1
    fi
    if jq -e '.scripts.test' package.json &>/dev/null; then
      run_cmd "npm test" || RESULT=1
    fi
    if jq -e '.scripts.lint' package.json &>/dev/null; then
      run_cmd "npm run lint" || RESULT=1
    fi
  fi
fi

# Rust (Cargo.toml)
if [ -f "Cargo.toml" ]; then
  log "Detected: Rust project"
  if command -v cargo &>/dev/null; then
    run_cmd "cargo build" || RESULT=1
    run_cmd "cargo test" || RESULT=1
  fi
fi

# Go (go.mod)
if [ -f "go.mod" ]; then
  log "Detected: Go project"
  if command -v go &>/dev/null; then
    run_cmd "go build ./..." || RESULT=1
    run_cmd "go test ./..." || RESULT=1
  fi
fi

# Python (pyproject.toml or setup.py)
if [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  log "Detected: Python project"
  if command -v pytest &>/dev/null; then
    run_cmd "pytest" || RESULT=1
  elif command -v python3 &>/dev/null && [ -d "tests" ]; then
    run_cmd "python3 -m pytest" || RESULT=1
  fi
fi

# Makefile
if [ -f "Makefile" ]; then
  log "Detected: Makefile"
  if grep -q '^build:' Makefile 2>/dev/null; then
    run_cmd "make build" || RESULT=1
  fi
  if grep -q '^test:' Makefile 2>/dev/null; then
    run_cmd "make test" || RESULT=1
  fi
fi

if [ "$RESULT" -eq 0 ]; then
  log "All checks passed"
else
  log "Some checks failed"
fi

exit "$RESULT"
