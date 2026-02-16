# Pipeline JSON Schema 정식 설계

> 날짜: 2026-02-16
> 주제: 루프, 병렬 실행, 조건 분기, e2e 검증을 지원하는 파이프라인 JSON 스키마

---

## 1. 설계 원칙

### 1.1 기존 초안의 한계

`docs/research-pipeline-visual-editor-20260216.md`의 초안 스키마는 다음 한계가 있었다:

| 항목 | 초안 | 한계 |
|------|------|------|
| 루프 | `retry_count` 노드 속성 | 단일 노드 재시도만 가능. 다단계 루프(code -> test -> 실패 시 code로 복귀) 불가능 |
| 병렬 | Fork/Join 노드 | 노드는 있으나 Join의 대기 정책(all/any)이 없음 |
| 조건 분기 | ok/fail 포트 | 이진 분기만 가능. 다중 조건(exit_code, output 패턴 등) 불가능 |
| e2e 검증 | 없음 | 파이프라인 성공/실패 판정 기준이 없음 |
| 변수 전달 | `variables` 객체 | 노드 간 데이터 흐름이 불명확 |

### 1.2 설계 목표

1. **그래프 기반**: React Flow의 nodes/edges 구조와 1:1 호환
2. **Orchestrator 친화적**: LLM이 JSON을 읽고 실행 순서를 파악하기 쉬운 구조
3. **루프 표현**: 엣지 기반 루프백 + 최대 재시도 횟수로 무한 루프 방지
4. **병렬 표현**: Fork/Join 패턴 + Join 정책(all/any/N)
5. **조건 분기**: 다중 포트 + 조건 표현식
6. **e2e 검증**: 파이프라인 종료 시 성공 기준 평가
7. **확장 가능**: 향후 서브파이프라인, 변수 바인딩 등 추가 가능

---

## 2. JSON Schema 정의

### 2.1 최상위 구조 (Pipeline)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://hoodcat-harness.local/pipeline/v1",
  "title": "Pipeline",
  "description": "hoodcat-harness 파이프라인 정의",
  "type": "object",
  "required": ["name", "version", "nodes", "edges"],
  "properties": {
    "name": {
      "type": "string",
      "description": "파이프라인 식별자 (파일명과 일치, kebab-case)",
      "pattern": "^[a-z0-9][a-z0-9-]*$"
    },
    "description": {
      "type": "string",
      "description": "파이프라인의 용도 설명"
    },
    "version": {
      "type": "string",
      "description": "스키마 버전",
      "const": "1.0"
    },
    "created": {
      "type": "string",
      "format": "date-time"
    },
    "modified": {
      "type": "string",
      "format": "date-time"
    },
    "tags": {
      "type": "array",
      "items": { "type": "string" },
      "description": "분류 태그 (feature, bugfix, hotfix, refactor 등)"
    },
    "variables": {
      "$ref": "#/$defs/Variables"
    },
    "validation": {
      "$ref": "#/$defs/Validation"
    },
    "nodes": {
      "type": "array",
      "items": { "$ref": "#/$defs/Node" },
      "minItems": 2,
      "description": "최소 Start + End 노드 필요"
    },
    "edges": {
      "type": "array",
      "items": { "$ref": "#/$defs/Edge" }
    }
  }
}
```

### 2.2 Variables (파이프라인 전역 변수)

```json
{
  "$defs": {
    "Variables": {
      "type": "object",
      "description": "파이프라인 전역 변수. 런타임에 Orchestrator가 채움. 노드 args에서 ${var_name}으로 참조",
      "properties": {
        "worktree_path": {
          "type": "string",
          "description": "Orchestrator가 생성한 worktree 경로"
        },
        "branch_name": {
          "type": "string",
          "description": "작업 브랜치명"
        },
        "user_request": {
          "type": "string",
          "description": "사용자의 원본 요청"
        }
      },
      "additionalProperties": {
        "type": "string"
      }
    }
  }
}
```

### 2.3 Validation (e2e 검증)

```json
{
  "Validation": {
    "type": "object",
    "description": "파이프라인 완료 시 성공 판정 기준",
    "properties": {
      "criteria": {
        "type": "array",
        "items": {
          "type": "object",
          "required": ["name", "check"],
          "properties": {
            "name": {
              "type": "string",
              "description": "검증 항목명 (예: 'tests_pass', 'no_lint_errors')"
            },
            "check": {
              "type": "string",
              "enum": ["all_nodes_ok", "exit_code_zero", "output_contains", "output_not_contains", "custom_command"],
              "description": "검증 방법"
            },
            "target_node": {
              "type": "string",
              "description": "검증 대상 노드 ID (check가 노드 결과를 참조할 때)"
            },
            "value": {
              "type": "string",
              "description": "output_contains/not_contains의 매칭 문자열, custom_command의 실행 명령"
            },
            "severity": {
              "type": "string",
              "enum": ["error", "warning"],
              "default": "error",
              "description": "error: 실패 시 파이프라인 실패, warning: 경고만 출력"
            }
          }
        }
      },
      "on_failure": {
        "type": "string",
        "enum": ["abort", "report"],
        "default": "report",
        "description": "검증 실패 시 동작. abort: 즉시 중단, report: 결과를 보고하고 사용자에게 판단 위임"
      }
    }
  }
}
```

### 2.4 Node (노드 정의)

```json
{
  "Node": {
    "type": "object",
    "required": ["id", "type"],
    "properties": {
      "id": {
        "type": "string",
        "description": "노드 고유 식별자",
        "pattern": "^[a-z0-9][a-z0-9-]*$"
      },
      "type": {
        "type": "string",
        "enum": ["start", "end", "skill", "agent", "fork", "join", "condition", "loop"],
        "description": "노드 유형"
      },
      "label": {
        "type": "string",
        "description": "UI에 표시되는 노드 이름 (선택)"
      },
      "position": {
        "type": "object",
        "properties": {
          "x": { "type": "number" },
          "y": { "type": "number" }
        },
        "description": "UI 레이아웃용 좌표. Orchestrator는 무시"
      },
      "data": {
        "description": "노드 유형별 데이터",
        "oneOf": [
          { "$ref": "#/$defs/StartData" },
          { "$ref": "#/$defs/EndData" },
          { "$ref": "#/$defs/SkillData" },
          { "$ref": "#/$defs/AgentData" },
          { "$ref": "#/$defs/ForkData" },
          { "$ref": "#/$defs/JoinData" },
          { "$ref": "#/$defs/ConditionData" },
          { "$ref": "#/$defs/LoopData" }
        ]
      }
    }
  }
}
```

#### 2.4.1 Start / End 노드

```json
{
  "StartData": {
    "type": "object",
    "description": "파이프라인 진입점. 포트: out(ok)",
    "properties": {}
  },
  "EndData": {
    "type": "object",
    "description": "파이프라인 종료점. 포트: in",
    "properties": {
      "status": {
        "type": "string",
        "enum": ["success", "failure", "conditional"],
        "default": "conditional",
        "description": "종료 상태. conditional이면 마지막 도달 노드의 결과로 판정"
      }
    }
  }
}
```

#### 2.4.2 Skill 노드

```json
{
  "SkillData": {
    "type": "object",
    "required": ["skill"],
    "description": "스킬 실행 노드. 포트: in, ok, fail",
    "properties": {
      "skill": {
        "type": "string",
        "enum": ["code", "test", "blueprint", "commit", "deploy", "security-scan", "deepresearch", "decide", "scaffold", "team-review", "qa-swarm"],
        "description": "실행할 스킬 식별자"
      },
      "args": {
        "type": "string",
        "description": "스킬에 전달할 인자. ${variable}으로 변수 참조 가능"
      },
      "retry": {
        "$ref": "#/$defs/RetryConfig"
      }
    }
  }
}
```

#### 2.4.3 Agent 노드

```json
{
  "AgentData": {
    "type": "object",
    "required": ["agent"],
    "description": "에이전트 Task() 호출 노드. 포트: in, ok, fail",
    "properties": {
      "agent": {
        "type": "string",
        "enum": ["navigator", "reviewer", "security", "architect"],
        "description": "호출할 에이전트"
      },
      "prompt": {
        "type": "string",
        "description": "에이전트에 전달할 프롬프트. ${variable}으로 변수 참조 가능"
      },
      "retry": {
        "$ref": "#/$defs/RetryConfig"
      }
    }
  }
}
```

#### 2.4.4 Fork 노드 (병렬 분기)

```json
{
  "ForkData": {
    "type": "object",
    "description": "병렬 실행 분기점. 포트: in, out-0, out-1, ..., out-N",
    "properties": {
      "branches": {
        "type": "integer",
        "minimum": 2,
        "description": "병렬 분기 수. UI에서 out-0 ~ out-(N-1) 포트 생성"
      }
    }
  }
}
```

#### 2.4.5 Join 노드 (병렬 합류)

```json
{
  "JoinData": {
    "type": "object",
    "description": "병렬 실행 합류점. 포트: in-0, in-1, ..., in-N, ok, fail",
    "properties": {
      "wait_policy": {
        "type": "string",
        "enum": ["all", "any", "n_of"],
        "default": "all",
        "description": "all: 모든 분기 완료 대기, any: 하나라도 완료, n_of: N개 완료"
      },
      "wait_count": {
        "type": "integer",
        "minimum": 1,
        "description": "wait_policy가 n_of일 때 대기할 분기 수"
      },
      "fail_policy": {
        "type": "string",
        "enum": ["any_fail", "all_fail", "ignore"],
        "default": "any_fail",
        "description": "any_fail: 하나라도 실패하면 Join 실패, all_fail: 모두 실패해야 실패, ignore: 실패 무시"
      }
    }
  }
}
```

#### 2.4.6 Condition 노드 (조건 분기)

```json
{
  "ConditionData": {
    "type": "object",
    "required": ["conditions"],
    "description": "다중 조건 분기. 포트: in, 조건별 출력 포트, default",
    "properties": {
      "conditions": {
        "type": "array",
        "items": {
          "type": "object",
          "required": ["port", "check"],
          "properties": {
            "port": {
              "type": "string",
              "description": "이 조건이 참일 때 사용할 출력 포트명"
            },
            "check": {
              "type": "string",
              "enum": ["prev_ok", "prev_fail", "var_equals", "var_contains", "output_contains"],
              "description": "조건 검사 유형"
            },
            "variable": {
              "type": "string",
              "description": "var_equals, var_contains에서 검사할 변수명"
            },
            "value": {
              "type": "string",
              "description": "비교 대상 값"
            }
          }
        }
      },
      "default_port": {
        "type": "string",
        "default": "default",
        "description": "어떤 조건도 만족하지 않을 때 사용할 포트"
      },
      "evaluate_from": {
        "type": "string",
        "description": "결과를 참조할 노드 ID (미지정 시 직전 노드)"
      }
    }
  }
}
```

#### 2.4.7 Loop 노드 (반복)

```json
{
  "LoopData": {
    "type": "object",
    "required": ["max_iterations"],
    "description": "반복 제어 노드. 내부 서브그래프를 반복 실행. 포트: in, body(루프 본문 시작), ok(루프 정상 종료), fail(max 초과)",
    "properties": {
      "max_iterations": {
        "type": "integer",
        "minimum": 1,
        "maximum": 10,
        "description": "최대 반복 횟수. 무한 루프 방지"
      },
      "exit_condition": {
        "type": "string",
        "enum": ["body_ok", "body_fail", "var_equals"],
        "default": "body_ok",
        "description": "루프 종료 조건. body_ok: 본문이 성공하면 종료, body_fail: 본문이 실패하면 종료"
      },
      "exit_variable": {
        "type": "string",
        "description": "var_equals일 때 검사할 변수명"
      },
      "exit_value": {
        "type": "string",
        "description": "var_equals일 때 비교 값"
      },
      "loop_back_to": {
        "type": "string",
        "description": "루프백 대상 노드 ID. 이 노드부터 다시 실행"
      }
    }
  }
}
```

#### 2.4.8 RetryConfig (노드 단위 재시도)

```json
{
  "RetryConfig": {
    "type": "object",
    "description": "노드 단위 자동 재시도 설정",
    "properties": {
      "max_retries": {
        "type": "integer",
        "minimum": 0,
        "maximum": 5,
        "default": 0,
        "description": "최대 재시도 횟수. 0이면 재시도 안 함"
      },
      "retry_on": {
        "type": "string",
        "enum": ["fail", "timeout"],
        "default": "fail",
        "description": "재시도 트리거. fail: 실패 시, timeout: 타임아웃 시"
      },
      "backoff_seconds": {
        "type": "integer",
        "minimum": 0,
        "default": 0,
        "description": "재시도 간 대기 시간(초)"
      }
    }
  }
}
```

### 2.5 Edge (엣지 정의)

```json
{
  "Edge": {
    "type": "object",
    "required": ["id", "source", "target", "sourceHandle"],
    "properties": {
      "id": {
        "type": "string",
        "description": "엣지 고유 식별자"
      },
      "source": {
        "type": "string",
        "description": "출발 노드 ID"
      },
      "target": {
        "type": "string",
        "description": "도착 노드 ID"
      },
      "sourceHandle": {
        "type": "string",
        "description": "출발 포트. ok, fail, out-0, out-1, body, default, 조건포트명 등"
      },
      "targetHandle": {
        "type": "string",
        "default": "in",
        "description": "도착 포트. 일반적으로 in, Join은 in-0, in-1 등"
      },
      "label": {
        "type": "string",
        "description": "UI에 표시되는 엣지 레이블 (선택)"
      },
      "animated": {
        "type": "boolean",
        "default": false,
        "description": "UI에서 애니메이션 표시 여부 (루프백 엣지 등에 사용)"
      },
      "style": {
        "type": "object",
        "properties": {
          "stroke": { "type": "string" },
          "strokeDasharray": { "type": "string" }
        },
        "description": "UI 스타일. Orchestrator는 무시"
      }
    }
  }
}
```

---

## 3. 노드별 포트 규격

각 노드 유형이 가지는 포트를 정리한다. Orchestrator가 엣지를 해석할 때 이 규격을 참조한다.

| 노드 유형 | 입력 포트 | 출력 포트 | 비고 |
|-----------|----------|----------|------|
| `start` | (없음) | `ok` | 파이프라인 진입 |
| `end` | `in` | (없음) | 파이프라인 종료 |
| `skill` | `in` | `ok`, `fail` | 스킬 실행 결과에 따라 분기 |
| `agent` | `in` | `ok`, `fail` | 에이전트 실행 결과에 따라 분기 |
| `fork` | `in` | `out-0`, `out-1`, ..., `out-N` | 병렬 분기. branches 수만큼 출력 포트 |
| `join` | `in-0`, `in-1`, ..., `in-N` | `ok`, `fail` | 병렬 합류. wait_policy에 따라 ok/fail |
| `condition` | `in` | 조건별 포트명, `default` | 조건 평가 결과에 따라 분기 |
| `loop` | `in` | `body`, `ok`, `fail` | body: 루프 본문, ok: 정상 종료, fail: max 초과 |

---

## 4. 실행 시맨틱 (Orchestrator 실행 규칙)

Orchestrator가 파이프라인 JSON을 읽고 실행할 때 따라야 하는 규칙을 정의한다.

### 4.1 실행 흐름

1. **시작**: `start` 노드에서 `ok` 포트로 연결된 노드부터 실행
2. **순차 실행**: 현재 노드를 실행하고, 결과(ok/fail)에 따라 해당 포트의 엣지를 따라 다음 노드로 이동
3. **재시도**: `retry.max_retries > 0`이면, 실패 시 같은 노드를 재시도. 재시도 소진 후에도 실패하면 `fail` 포트로 이동
4. **포트 미연결**: `fail` 포트에 연결된 엣지가 없고 재시도도 소진되면 파이프라인 실패로 종료
5. **종료**: `end` 노드에 도달하면 파이프라인 종료

### 4.2 병렬 실행 (Fork/Join)

1. `fork` 노드 도달 시, 모든 `out-N` 포트의 대상 노드를 **동시에** 실행 시작
2. 각 분기는 독립적으로 `ok`/`fail` 경로를 따라 진행
3. 모든 분기가 `join` 노드의 입력 포트에 도달할 때까지 대기 (wait_policy에 따라)
4. `join` 노드의 `fail_policy`에 따라 전체 결과를 ok/fail로 판정
5. **Orchestrator 구현**: `Task(agent, run_in_background=true)`를 병렬 분기마다 호출하고, 모든 결과를 수집한 후 join 판정

### 4.3 루프 (Loop)

#### 방식 A: Loop 노드 사용 (명시적 서브그래프)

```
[loop-1] --body--> [code-1] --ok--> [test-1] --ok--> [loop-1의 ok 포트로]
                                     |
                                     fail --> [loop-1의 body 포트로 루프백]
```

실행 규칙:
1. `loop` 노드의 `body` 포트로 연결된 노드부터 루프 본문 시작
2. 본문 내 노드들이 순차 실행됨
3. `exit_condition`이 만족되면 `ok` 포트로 빠져나감
4. 만족되지 않으면 `body` 포트부터 다시 실행 (반복)
5. `max_iterations` 도달 시 `fail` 포트로 빠져나감

#### 방식 B: 엣지 기반 루프백 (간소화)

```
[code-1] --ok--> [test-1] --ok--> [다음 단계]
                           |
                           fail --> [code-1] (루프백 엣지, label: "fix & retry")
```

이 경우 Loop 노드 없이 fail 엣지가 이전 노드를 가리킨다.
**무한 루프 방지**: 엣지에 `maxTraversals` 속성을 추가한다.

```json
{
  "id": "e-loop-back",
  "source": "test-1",
  "target": "code-1",
  "sourceHandle": "fail",
  "label": "fix & retry",
  "maxTraversals": 3
}
```

#### 설계 결정: 두 방식 모두 지원

- **단순 재시도** (같은 노드 반복): `retry` 속성 사용
- **두 노드 간 루프** (code -> test -> 실패 시 code로): 엣지 기반 루프백 + `maxTraversals`
- **복잡한 다단계 루프** (3개 이상 노드 반복): Loop 노드 사용

### 4.4 조건 분기 (Condition)

1. `condition` 노드 도달 시, `conditions` 배열을 순서대로 평가
2. 첫 번째로 참인 조건의 `port`에 연결된 엣지를 따라 이동
3. 모든 조건이 거짓이면 `default_port`의 엣지를 따라 이동
4. `evaluate_from`이 지정되면 해당 노드의 실행 결과를 기준으로 평가

### 4.5 변수 참조

노드의 `args`와 `prompt` 필드에서 `${variable_name}` 구문으로 변수를 참조할 수 있다.

```json
{
  "skill": "code",
  "args": "${user_request} (worktree: ${worktree_path})"
}
```

Orchestrator는 실행 전에 변수를 치환한다. 치환 순서:
1. `variables`에 정의된 값
2. 런타임에 Orchestrator가 설정한 값 (worktree_path 등)
3. 이전 노드의 출력 결과 (`${node_id.output}` 형식, 향후 확장)

### 4.6 e2e 검증

파이프라인이 `end` 노드에 도달한 후:
1. `validation.criteria` 배열을 순서대로 평가
2. `all_nodes_ok`: 모든 실행된 노드가 ok로 완료되었는지 확인
3. `exit_code_zero`: 특정 노드의 exit code가 0인지 확인
4. `output_contains`: 특정 노드의 출력에 문자열이 포함되는지 확인
5. `custom_command`: 쉘 명령을 실행하여 exit code로 판정
6. severity가 `error`인 항목이 하나라도 실패하면 파이프라인 실패
7. `on_failure`에 따라 abort(즉시 중단) 또는 report(보고만)

---

## 5. 예시 파이프라인

### 5.1 Feature Implementation (기능 구현)

루프, 병렬, 조건 분기를 모두 사용하는 완전한 예시.

```
[start] -> [navigator] -> [code] -> [test] -ok-> [fork] -> [reviewer]  -> [join] -> [commit] -> [end]
                                      |                  -> [security] -^
                                      fail (루프백, max 3)
                                      |
                                      v
                                    [code] (fix)
```

```json
{
  "name": "feature-implementation",
  "description": "기능 구현 표준 파이프라인. 탐색 -> 코딩 -> 테스트(루프) -> 병렬 리뷰 -> 커밋",
  "version": "1.0",
  "created": "2026-02-16T00:00:00Z",
  "modified": "2026-02-16T00:00:00Z",
  "tags": ["feature", "standard"],

  "variables": {
    "worktree_path": "",
    "branch_name": "",
    "user_request": ""
  },

  "validation": {
    "criteria": [
      {
        "name": "all_nodes_completed",
        "check": "all_nodes_ok",
        "severity": "error"
      },
      {
        "name": "tests_pass",
        "check": "exit_code_zero",
        "target_node": "test-1",
        "severity": "error"
      }
    ],
    "on_failure": "report"
  },

  "nodes": [
    {
      "id": "start-1",
      "type": "start",
      "position": { "x": 0, "y": 250 }
    },
    {
      "id": "nav-1",
      "type": "agent",
      "label": "코드베이스 탐색",
      "data": {
        "agent": "navigator",
        "prompt": "${user_request}에 관련된 코드베이스 구조와 파일 탐색"
      },
      "position": { "x": 200, "y": 250 }
    },
    {
      "id": "code-1",
      "type": "skill",
      "label": "구현",
      "data": {
        "skill": "code",
        "args": "${user_request} (worktree: ${worktree_path})",
        "retry": {
          "max_retries": 1,
          "retry_on": "fail"
        }
      },
      "position": { "x": 450, "y": 250 }
    },
    {
      "id": "test-1",
      "type": "skill",
      "label": "테스트",
      "data": {
        "skill": "test",
        "args": "구현된 코드에 대한 테스트 실행 (worktree: ${worktree_path})"
      },
      "position": { "x": 700, "y": 250 }
    },
    {
      "id": "fork-1",
      "type": "fork",
      "label": "병렬 리뷰",
      "data": {
        "branches": 2
      },
      "position": { "x": 950, "y": 250 }
    },
    {
      "id": "review-1",
      "type": "agent",
      "label": "코드 리뷰",
      "data": {
        "agent": "reviewer",
        "prompt": "구현된 코드의 품질 리뷰"
      },
      "position": { "x": 1200, "y": 150 }
    },
    {
      "id": "security-1",
      "type": "agent",
      "label": "보안 리뷰",
      "data": {
        "agent": "security",
        "prompt": "보안 취약점 검토"
      },
      "position": { "x": 1200, "y": 350 }
    },
    {
      "id": "join-1",
      "type": "join",
      "label": "리뷰 합류",
      "data": {
        "wait_policy": "all",
        "fail_policy": "any_fail"
      },
      "position": { "x": 1450, "y": 250 }
    },
    {
      "id": "commit-1",
      "type": "skill",
      "label": "커밋",
      "data": {
        "skill": "commit",
        "args": "(worktree: ${worktree_path})"
      },
      "position": { "x": 1700, "y": 250 }
    },
    {
      "id": "end-1",
      "type": "end",
      "data": {
        "status": "conditional"
      },
      "position": { "x": 1950, "y": 250 }
    }
  ],

  "edges": [
    { "id": "e1", "source": "start-1", "target": "nav-1", "sourceHandle": "ok" },
    { "id": "e2", "source": "nav-1", "target": "code-1", "sourceHandle": "ok" },
    { "id": "e3", "source": "code-1", "target": "test-1", "sourceHandle": "ok" },
    { "id": "e4", "source": "test-1", "target": "fork-1", "sourceHandle": "ok" },
    {
      "id": "e5-loop",
      "source": "test-1",
      "target": "code-1",
      "sourceHandle": "fail",
      "label": "fix & retry",
      "maxTraversals": 3,
      "animated": true,
      "style": { "strokeDasharray": "5,5" }
    },
    { "id": "e6", "source": "fork-1", "target": "review-1", "sourceHandle": "out-0" },
    { "id": "e7", "source": "fork-1", "target": "security-1", "sourceHandle": "out-1" },
    { "id": "e8", "source": "review-1", "target": "join-1", "sourceHandle": "ok", "targetHandle": "in-0" },
    { "id": "e9", "source": "security-1", "target": "join-1", "sourceHandle": "ok", "targetHandle": "in-1" },
    { "id": "e10", "source": "join-1", "target": "commit-1", "sourceHandle": "ok" },
    { "id": "e11", "source": "commit-1", "target": "end-1", "sourceHandle": "ok" }
  ]
}
```

### 5.2 Bug Fix with Diagnosis (버그 수정 + 진단 루프)

Loop 노드를 사용한 다단계 루프 예시.

```
[start] -> [loop-1] --body--> [code(진단+패치)] -> [test] --ok--> [loop-1 ok]
                                                     |
                                                     fail --> [loop-1 body로 루프백]
           [loop-1 ok] -> [reviewer] -> [commit] -> [end]
           [loop-1 fail] -> [end-fail]
```

```json
{
  "name": "bugfix-with-diagnosis",
  "description": "버그 수정 파이프라인. 진단 -> 패치 -> 테스트를 루프하여 테스트 통과까지 반복",
  "version": "1.0",
  "created": "2026-02-16T00:00:00Z",
  "modified": "2026-02-16T00:00:00Z",
  "tags": ["bugfix", "loop"],

  "variables": {
    "worktree_path": "",
    "branch_name": "",
    "user_request": "",
    "bug_description": ""
  },

  "validation": {
    "criteria": [
      {
        "name": "regression_test",
        "check": "exit_code_zero",
        "target_node": "test-1",
        "severity": "error"
      }
    ],
    "on_failure": "report"
  },

  "nodes": [
    {
      "id": "start-1",
      "type": "start",
      "position": { "x": 0, "y": 200 }
    },
    {
      "id": "loop-1",
      "type": "loop",
      "label": "진단-패치-테스트 루프",
      "data": {
        "max_iterations": 3,
        "exit_condition": "body_ok",
        "loop_back_to": "code-1"
      },
      "position": { "x": 200, "y": 200 }
    },
    {
      "id": "code-1",
      "type": "skill",
      "label": "진단 + 패치",
      "data": {
        "skill": "code",
        "args": "버그 진단 및 수정: ${bug_description} (worktree: ${worktree_path})"
      },
      "position": { "x": 450, "y": 200 }
    },
    {
      "id": "test-1",
      "type": "skill",
      "label": "회귀 테스트",
      "data": {
        "skill": "test",
        "args": "회귀 테스트 실행 (worktree: ${worktree_path})"
      },
      "position": { "x": 700, "y": 200 }
    },
    {
      "id": "review-1",
      "type": "agent",
      "label": "코드 리뷰",
      "data": {
        "agent": "reviewer",
        "prompt": "버그 수정 코드 리뷰"
      },
      "position": { "x": 950, "y": 200 }
    },
    {
      "id": "commit-1",
      "type": "skill",
      "label": "커밋",
      "data": {
        "skill": "commit",
        "args": "(worktree: ${worktree_path})"
      },
      "position": { "x": 1200, "y": 200 }
    },
    {
      "id": "end-ok",
      "type": "end",
      "label": "성공",
      "data": { "status": "success" },
      "position": { "x": 1450, "y": 200 }
    },
    {
      "id": "end-fail",
      "type": "end",
      "label": "실패 (재시도 초과)",
      "data": { "status": "failure" },
      "position": { "x": 450, "y": 400 }
    }
  ],

  "edges": [
    { "id": "e1", "source": "start-1", "target": "loop-1", "sourceHandle": "ok" },
    { "id": "e2", "source": "loop-1", "target": "code-1", "sourceHandle": "body" },
    { "id": "e3", "source": "code-1", "target": "test-1", "sourceHandle": "ok" },
    {
      "id": "e4-loop",
      "source": "test-1",
      "target": "loop-1",
      "sourceHandle": "fail",
      "targetHandle": "in",
      "label": "retry loop",
      "animated": true
    },
    { "id": "e5", "source": "test-1", "target": "review-1", "sourceHandle": "ok" },
    { "id": "e6", "source": "loop-1", "target": "end-fail", "sourceHandle": "fail" },
    { "id": "e7", "source": "review-1", "target": "commit-1", "sourceHandle": "ok" },
    { "id": "e8", "source": "commit-1", "target": "end-ok", "sourceHandle": "ok" }
  ]
}
```

### 5.3 Security Hotfix (보안 핫픽스)

조건 분기 + 병렬 리뷰 예시.

```
[start] -> [security(심각도 평가)] -> [condition] --critical--> [code(즉시 패치)] -> [fork] -> [reviewer]  -> [join] -> [security-scan] -> [test] -> [commit] -> [end]
                                                                                           -> [security] -^
                                       --low/medium--> [code(일반 패치)] -> [test] -> [reviewer] -> [commit] -> [end]
```

```json
{
  "name": "security-hotfix",
  "description": "보안 핫픽스 파이프라인. 심각도에 따라 경로 분기, 병렬 보안+코드 리뷰",
  "version": "1.0",
  "created": "2026-02-16T00:00:00Z",
  "modified": "2026-02-16T00:00:00Z",
  "tags": ["hotfix", "security"],

  "variables": {
    "worktree_path": "",
    "branch_name": "",
    "user_request": "",
    "severity": ""
  },

  "validation": {
    "criteria": [
      {
        "name": "security_scan_clean",
        "check": "exit_code_zero",
        "target_node": "scan-1",
        "severity": "error"
      },
      {
        "name": "tests_pass",
        "check": "all_nodes_ok",
        "severity": "error"
      }
    ],
    "on_failure": "abort"
  },

  "nodes": [
    {
      "id": "start-1",
      "type": "start",
      "position": { "x": 0, "y": 300 }
    },
    {
      "id": "sec-assess",
      "type": "agent",
      "label": "심각도 평가",
      "data": {
        "agent": "security",
        "prompt": "보안 취약점 심각도 평가: ${user_request}"
      },
      "position": { "x": 200, "y": 300 }
    },
    {
      "id": "cond-1",
      "type": "condition",
      "label": "심각도 분기",
      "data": {
        "conditions": [
          {
            "port": "critical",
            "check": "var_equals",
            "variable": "severity",
            "value": "critical"
          },
          {
            "port": "high",
            "check": "var_equals",
            "variable": "severity",
            "value": "high"
          }
        ],
        "default_port": "normal",
        "evaluate_from": "sec-assess"
      },
      "position": { "x": 450, "y": 300 }
    },

    {
      "id": "code-critical",
      "type": "skill",
      "label": "긴급 패치",
      "data": {
        "skill": "code",
        "args": "보안 긴급 패치: ${user_request} (worktree: ${worktree_path})",
        "retry": { "max_retries": 1, "retry_on": "fail" }
      },
      "position": { "x": 700, "y": 150 }
    },
    {
      "id": "fork-critical",
      "type": "fork",
      "data": { "branches": 2 },
      "position": { "x": 950, "y": 150 }
    },
    {
      "id": "review-critical",
      "type": "agent",
      "label": "코드 리뷰",
      "data": {
        "agent": "reviewer",
        "prompt": "긴급 보안 패치 코드 리뷰"
      },
      "position": { "x": 1200, "y": 50 }
    },
    {
      "id": "sec-critical",
      "type": "agent",
      "label": "보안 재검토",
      "data": {
        "agent": "security",
        "prompt": "패치 후 보안 재검토"
      },
      "position": { "x": 1200, "y": 250 }
    },
    {
      "id": "join-critical",
      "type": "join",
      "data": {
        "wait_policy": "all",
        "fail_policy": "any_fail"
      },
      "position": { "x": 1450, "y": 150 }
    },
    {
      "id": "scan-1",
      "type": "skill",
      "label": "보안 스캔",
      "data": {
        "skill": "security-scan",
        "args": "(worktree: ${worktree_path})"
      },
      "position": { "x": 1700, "y": 150 }
    },
    {
      "id": "test-critical",
      "type": "skill",
      "label": "회귀 테스트",
      "data": {
        "skill": "test",
        "args": "회귀 테스트 (worktree: ${worktree_path})"
      },
      "position": { "x": 1950, "y": 150 }
    },
    {
      "id": "commit-critical",
      "type": "skill",
      "label": "커밋",
      "data": {
        "skill": "commit",
        "args": "(worktree: ${worktree_path})"
      },
      "position": { "x": 2200, "y": 150 }
    },

    {
      "id": "code-normal",
      "type": "skill",
      "label": "일반 패치",
      "data": {
        "skill": "code",
        "args": "보안 패치: ${user_request} (worktree: ${worktree_path})",
        "retry": { "max_retries": 2, "retry_on": "fail" }
      },
      "position": { "x": 700, "y": 450 }
    },
    {
      "id": "test-normal",
      "type": "skill",
      "label": "테스트",
      "data": {
        "skill": "test",
        "args": "테스트 실행 (worktree: ${worktree_path})"
      },
      "position": { "x": 950, "y": 450 }
    },
    {
      "id": "review-normal",
      "type": "agent",
      "label": "코드 리뷰",
      "data": {
        "agent": "reviewer",
        "prompt": "보안 패치 코드 리뷰"
      },
      "position": { "x": 1200, "y": 450 }
    },
    {
      "id": "commit-normal",
      "type": "skill",
      "label": "커밋",
      "data": {
        "skill": "commit",
        "args": "(worktree: ${worktree_path})"
      },
      "position": { "x": 1450, "y": 450 }
    },

    {
      "id": "end-1",
      "type": "end",
      "data": { "status": "conditional" },
      "position": { "x": 2450, "y": 300 }
    }
  ],

  "edges": [
    { "id": "e1", "source": "start-1", "target": "sec-assess", "sourceHandle": "ok" },
    { "id": "e2", "source": "sec-assess", "target": "cond-1", "sourceHandle": "ok" },

    { "id": "e3", "source": "cond-1", "target": "code-critical", "sourceHandle": "critical" },
    { "id": "e4", "source": "cond-1", "target": "code-critical", "sourceHandle": "high" },
    { "id": "e5", "source": "code-critical", "target": "fork-critical", "sourceHandle": "ok" },
    { "id": "e6", "source": "fork-critical", "target": "review-critical", "sourceHandle": "out-0" },
    { "id": "e7", "source": "fork-critical", "target": "sec-critical", "sourceHandle": "out-1" },
    { "id": "e8", "source": "review-critical", "target": "join-critical", "sourceHandle": "ok", "targetHandle": "in-0" },
    { "id": "e9", "source": "sec-critical", "target": "join-critical", "sourceHandle": "ok", "targetHandle": "in-1" },
    { "id": "e10", "source": "join-critical", "target": "scan-1", "sourceHandle": "ok" },
    { "id": "e11", "source": "scan-1", "target": "test-critical", "sourceHandle": "ok" },
    { "id": "e12", "source": "test-critical", "target": "commit-critical", "sourceHandle": "ok" },
    { "id": "e13", "source": "commit-critical", "target": "end-1", "sourceHandle": "ok" },

    { "id": "e14", "source": "cond-1", "target": "code-normal", "sourceHandle": "normal" },
    { "id": "e15", "source": "code-normal", "target": "test-normal", "sourceHandle": "ok" },
    { "id": "e16", "source": "test-normal", "target": "review-normal", "sourceHandle": "ok" },
    { "id": "e17", "source": "review-normal", "target": "commit-normal", "sourceHandle": "ok" },
    { "id": "e18", "source": "commit-normal", "target": "end-1", "sourceHandle": "ok" },

    {
      "id": "e19-loop",
      "source": "test-normal",
      "target": "code-normal",
      "sourceHandle": "fail",
      "label": "fix & retry",
      "maxTraversals": 2,
      "animated": true
    }
  ]
}
```

---

## 6. React Flow 호환성

### 6.1 매핑 규칙

이 스키마는 React Flow의 `Node`와 `Edge` 타입에 직접 매핑 가능하다.

| 스키마 필드 | React Flow 필드 | 비고 |
|------------|----------------|------|
| `node.id` | `Node.id` | 1:1 |
| `node.type` | `Node.type` | 커스텀 노드 유형으로 등록 |
| `node.position` | `Node.position` | 1:1 |
| `node.data` | `Node.data` | 커스텀 노드 컴포넌트가 props로 받음 |
| `node.label` | `Node.data.label` | React Flow 관례에 따라 data 안에 배치 |
| `edge.id` | `Edge.id` | 1:1 |
| `edge.source` | `Edge.source` | 1:1 |
| `edge.target` | `Edge.target` | 1:1 |
| `edge.sourceHandle` | `Edge.sourceHandle` | 1:1 |
| `edge.targetHandle` | `Edge.targetHandle` | 1:1 |
| `edge.label` | `Edge.label` | 1:1 |
| `edge.animated` | `Edge.animated` | 1:1 |
| `edge.style` | `Edge.style` | 1:1 |

### 6.2 커스텀 필드 처리

React Flow가 인식하지 못하는 필드:
- `edge.maxTraversals`: React Flow 무시. Orchestrator 전용.
- `node.data.retry`: React Flow 무시. UI 설정 패널에서 편집.
- `variables`, `validation`: 파이프라인 최상위 메타데이터. React Flow와 무관.

### 6.3 직렬화/역직렬화

```
UI -> JSON: React Flow 상태(nodes, edges) + 메타데이터(name, variables, validation) = Pipeline JSON
JSON -> UI: Pipeline JSON에서 nodes, edges 추출 -> React Flow 상태로 로드
```

React Flow의 `useNodesState`, `useEdgesState`로 직접 관리 가능하므로 별도 변환 없이 nodes/edges 배열을 그대로 사용한다.

---

## 7. Orchestrator 실행 용이성 검증

### 7.1 LLM이 파악해야 할 것

Orchestrator(LLM)가 이 JSON을 읽고 실행하려면 다음을 정확히 파악해야 한다:

| 항목 | 방법 | 난이도 |
|------|------|--------|
| 실행 시작점 | `type: "start"` 노드 찾기 | 쉬움 |
| 다음 노드 결정 | 현재 노드의 결과(ok/fail)에 해당하는 엣지의 target 찾기 | 보통 |
| 병렬 실행 | fork 노드의 out-N 포트별 target을 병렬 호출 | 보통 |
| 병렬 합류 | join 노드에 모든 입력이 도착할 때까지 대기 | 보통 |
| 루프 | maxTraversals 카운터 관리, 루프백 엣지 추적 | 어려움 |
| 조건 분기 | conditions 배열 순회, 첫 번째 참 조건의 포트 선택 | 보통 |
| 변수 치환 | `${var}` 패턴을 variables 값으로 교체 | 쉬움 |

### 7.2 LLM 실행 지원 전략

LLM이 복잡한 그래프를 정확히 순회하는 것은 어렵다. 다음 전략으로 보완한다:

**전략 1: 토폴로지 정렬 전처리**

파이프라인 JSON을 로드할 때 전처리 스크립트가 실행 순서를 계산하여 `execution_order` 배열을 추가한다:

```json
{
  "execution_order": [
    { "step": 1, "node": "nav-1", "type": "agent" },
    { "step": 2, "node": "code-1", "type": "skill" },
    { "step": 3, "node": "test-1", "type": "skill", "on_fail": "goto_step_2", "max_retries": 3 },
    { "step": 4, "node": ["review-1", "security-1"], "type": "parallel" },
    { "step": 5, "node": "commit-1", "type": "skill" }
  ]
}
```

이 배열은 LLM이 순서대로 따라가기 쉬운 선형 구조다.

**전략 2: 실행 프로토콜 프롬프트**

Orchestrator의 프롬프트에 파이프라인 실행 프로토콜을 추가한다:

```
파이프라인 실행 시:
1. execution_order가 있으면 그것을 따른다
2. 없으면 start 노드에서 시작하여 엣지를 따라 순회한다
3. 각 step에서:
   - skill: Skill(data.skill, data.args)
   - agent: Task(data.agent, data.prompt)
   - parallel: 배열의 모든 노드를 동시 실행
   - on_fail: goto_step_N이면 해당 step으로 이동 (횟수 추적)
```

**전략 3: 단계별 실행 로그**

Orchestrator가 실행 중 각 단계의 상태를 기록한다:

```
Step 1 (nav-1): OK
Step 2 (code-1): OK
Step 3 (test-1): FAIL -> goto_step_2 (retry 1/3)
Step 2 (code-1): OK
Step 3 (test-1): OK
Step 4 (review-1, security-1): parallel start
  - review-1: OK
  - security-1: OK (warn: minor issue)
Step 5 (commit-1): OK
```

### 7.3 권장 구현 순서

1. **Phase 1**: `execution_order` 전처리 스크립트 구현 (가장 효과적)
2. **Phase 2**: Orchestrator 프롬프트에 실행 프로토콜 추가
3. **Phase 3**: UI에서 파이프라인 실행 시 자동으로 `execution_order` 생성

---

## 8. 초안 대비 변경 요약

| 항목 | 초안 | 정식 스키마 | 변경 이유 |
|------|------|-----------|----------|
| 루프 | `retry_count` 노드 속성 | 3단계: retry(노드 단위) + maxTraversals(엣지 루프백) + Loop 노드 | 단순 재시도부터 다단계 루프까지 표현 |
| 병렬 | Fork/Join 있으나 정책 없음 | `wait_policy`(all/any/n_of), `fail_policy`(any_fail/all_fail/ignore) | 유연한 병렬 합류 전략 |
| 조건 분기 | ok/fail 이진 분기만 | Condition 노드 + 다중 포트 + 조건 표현식 | 심각도별 분기 등 다중 경로 |
| e2e 검증 | 없음 | `validation` 객체 + criteria 배열 | 파이프라인 성공 판정 기준 명확화 |
| 변수 | 기본 `variables` 객체 | `${var}` 참조 구문 + 런타임 치환 | 노드 간 데이터 전달 표준화 |
| 엣지 | 기본 React Flow 호환 | `maxTraversals` 추가, `targetHandle` 명시화 | 루프 제어, Join 연결 명확화 |
| 실행 지원 | 없음 | `execution_order` 전처리, 실행 로그 | LLM 그래프 순회 정확도 보완 |

---

## 9. 제약사항 및 향후 확장

### 9.1 현재 스키마의 제약

- **서브파이프라인 미지원**: 파이프라인 안에서 다른 파이프라인을 호출하는 것은 미지원. 향후 `type: "pipeline"` 노드로 확장 가능
- **동적 분기 수 미지원**: Fork의 branches 수가 정적. 런타임에 조건에 따라 분기 수를 변경하는 것은 미지원
- **노드 간 데이터 전달 제한**: 현재 `${var}` 전역 변수만 지원. 이전 노드의 출력을 다음 노드의 입력으로 직접 바인딩하는 것은 향후 `${node_id.output}` 구문으로 확장
- **타임아웃 미지원**: 노드별/파이프라인 전체 타임아웃 설정이 없음. 향후 추가 가능

### 9.2 향후 확장 계획

| 버전 | 확장 | 설명 |
|------|------|------|
| 1.1 | 노드 간 데이터 바인딩 | `${node_id.output}`, `${node_id.exit_code}` |
| 1.1 | 타임아웃 | 노드별 `timeout_seconds`, 파이프라인 전체 `max_duration` |
| 1.2 | 서브파이프라인 | `type: "pipeline"` 노드, `data.pipeline: "other-pipeline"` |
| 1.2 | 동적 Fork | `data.branches: "dynamic"`, 조건에 따라 분기 수 결정 |
| 2.0 | 이벤트 트리거 | 파일 변경, 시간 트리거로 파이프라인 자동 실행 |

---

## 10. 주요 포인트 요약

1. **노드 8종**: start, end, skill(11개), agent(4개), fork, join, condition, loop
2. **루프 3단계**: retry(노드 자체) < maxTraversals(엣지 루프백) < Loop 노드(다단계)
3. **병렬**: Fork/Join + wait_policy + fail_policy
4. **조건 분기**: Condition 노드 + 다중 조건 + default 포트
5. **e2e 검증**: validation.criteria + severity + on_failure
6. **변수**: `${var}` 참조 + 런타임 치환
7. **React Flow 100% 호환**: nodes/edges 1:1 매핑, 커스텀 필드는 data에 포함
8. **LLM 실행 보조**: execution_order 전처리로 그래프 순회 정확도 보완
9. **초안과 호환**: 기존 초안 구조를 확장한 것이므로 마이그레이션 용이
