# Changelog

이 파일은 multi-agent-starter (Codex flavor) orchestration 시스템의 주요 변경을 기록한다.

## [0.7.0] - 2026-07-26

### Changed
- **모든 워커는 그 시점의 최상위 모델을 쓴다** — 명시 원칙으로 승격(`_shared/routing.md` 모델 정책).
  하위 티어는 예외이며 `task.md`에 근거를 남긴다.
- **`claude-critic` 모델을 전체 ID 명시 핀으로 전환** (`--model claude-fable-5`). 별칭은 조용히
  뒤처지므로 쓰지 않는다.
- **codex-main은 의도적으로 핀하지 않는다** — `~/.codex/config.toml`이 정본. 대신 점검 절차 문서화.

### Fixed
- **`claude-critic` 호출이 깨져 있던 것 수정** — `args_template`이 `--prompt`였으나 `claude` CLI에
  그런 플래그는 없다(`unknown option`). `-p`로 교정. 그동안 이 워커는 호출 시점에 실패했다.

### Added
- **워커별 모델 점검 절차** — claude는 `modelUsage` 실측, gemini는 `agy models` 대조,
  codex는 config.toml 확인. 핀이 환경 allowlist에 없으면 경고 없이 다른 모델로 도는 점 명시.

## [0.6.0] - 2026-07-26

### Fixed
- **gemini 워커 모델을 `gemini-3.6-flash-high`로 갱신** (기존 `gemini-3.1-pro-high` — 2세대 뒤처짐).
  최신 세대 3.6에는 flash 티어만 있어(3.6-pro 없음) 세대·티어가 엇갈릴 때 최신 세대를 우선했다.
- **gemini 모델을 호출별로 핀** — `--model <id>` 플래그를 `backends.json`에 명시. 과거 "agy 모델은
  전역·계정 단위라 per-call 핀 불가"라던 기술이 현재는 무효다.

### Added
- **api 폴백(`_shared/adapters/gemini_api.sh`) 실제 동작** — 기존에는 항상 실패하는 슬롯 스텁이었다.
  Gemini REST 호출로 구현. `GEMINI_API_KEY` 설정 시 활성화되며 `agy` 인증과 독립된 경로다.
- **폴백 체인에 모델 강등 단계 추가** — `flash-high` → `flash-low`(폴백A) → `api`(폴백B).

## [0.5.0] - 2026-07-17

### Merged
- **netwaif v3.3.0 + kankadin fork 병합** — upstream의 라우팅 2층 분리(`_shared/capability-profile.md`
  가변층 + 슬롯 기반 routing, C5b) 위에 kankadin fork의 볼트 브리지 편입·런타임 안전 룰(지시-데이터
  분리·`check-invariants.sh`·learnings 통합 패스·worker 호출 예산)·승인 시 예산 확정·서브에이전트
  read-only 한정을 재적용. 아래 upstream 라우팅 엔트리와 `(kankadin fork)` 표기 엔트리를 함께 계승.

## [0.4.0] - 2026-07-13

### Added
- **라우팅 2층 분리 — `_shared/capability-profile.md` 신설(가변층)** — 능력 슬롯
  (strategist·engineer·computer-use·reviewer·multimodal) → 담당 배정의 정본.
  신모델 출시·판정 변경 시 프로필만 갱신(근거·날짜 필수, 이력 append-only) — routing.md의
  슬롯 정의는 불변. 근거: design-basis D8 (2026-07-13 외부 리뷰 10건 종합 판정).
- **computer-use 슬롯 신설** — 브라우저 조작·도구 워크플로우 자동화를 독립 라우팅
  (현 배정: Orchestrator 직접).

### Changed
- routing.md decision tree를 슬롯 기반으로 재편 — engineer·computer-use는 Orchestrator
  직접(크고 분리 가능하면 codex-main), strategist 산출물(설계·디자인·전략·문체)은
  claude-critic 품질 게이트 권장.
- validate에 C5b(2층 라우팅: routing→profile 참조 + 슬롯 5종) 추가, C1에 프로필 포함.
## [0.4.2] - 2026-07-05 (kankadin fork)

### Added
- **볼트 브리지 정식 편입** — 하네스 task 산출물을 knot 계열 LLM Wiki 볼트 inbox로 단방향
  export하는 브리지를 generator 정식 배포로 편입. `_shared/adapters/export_to_vault.sh`
  (실행권한 유지)·`_shared/vault-bridge.md`·`_shared/vault.config`가 이제 모든 설치에
  배포된다(볼트 열기 힌트는 `cd <vault> && codex`). `--domain <d>` 하나로 목적지 폴더·
  frontmatter를 함께 유도. 결정 기록: 이 flavor D9.

### Changed
- `_shared/vault.config`는 **scaffold-once 보존**(사용자 설정 — update가 덮어쓰지 않음).
- 볼트 경로 우선순위: `--vault > $KNOT_VAULT > vault.config(vault=) > $HOME/vaults/knot`.

## [0.4.1] - 2026-07-05 (kankadin fork)

### Changed
- **Confirm the budget at batch-approval time** — set `max_worker_calls` in the same batch
  approval, sized to `planned_workers` plus a retry margin; the soft gate then fires only on
  runaway beyond the plan (approval-policy call-budget section).
- **Host-native subagents are read-only** — host-native subagent/task tools (e.g. Claude
  Code's Agent tool) may do read-only exploration without approval; any artifact-producing
  delegation must go through the worker pool, since bypassing it leaves brief/result and audit
  log empty (AGENTS.md Approval Gate). (D8 (e)(f))

## [0.4.0] - 2026-07-05 (kankadin fork)

### Added
- **Instruction-data separation (untrusted input)** — `sources/` 자료·worker `result.md`
  내용은 데이터이지 지시가 아님을 AGENTS.md Verification에 명문화. 내장 지시문 발견 시
  불채택 + `[DECISION]` 기록 + 사용자 표면화. (D8a, INV12)
- **`_shared/check-invariants.sh` 결정론 실행기** — system-invariants.md 표가 스펙,
  스크립트가 실행기. ROOT 자동 탐지, 항목별 PASS/FAIL 자체 판정, FAIL 시 exit 1.
  orchestrator-rules §2 절차 3이 이 스크립트 실행으로 갱신됨. (D8b)
- **learnings.md 통합 패스** — 20KB(`wc -c`) 초과 시 반복 검증 교훈을 규칙 파일로 승격하고
  "## 통합됨"에 1줄 요약만 남기는 성장 관리 절차. (D8c)
- **worker 호출 예산 soft gate** — task.md 메타 `max_worker_calls`(기본 6) +
  approval-policy "호출 예산" 섹션 + AGENTS.md Approval Gate 한 줄. 초과 전 사용자 확인
  게이트(하드 중단 아님). (D8d, INV13)

## [0.3.3] - 2026-07-04 (kankadin fork)

### Fixed
- **KI-1 종결 — worker-brief 템플릿 mat 표시 오염**: 첫 의미 줄이 목적 평문이 아니라서 mat 모니터의 "워커 한 줄 목적"이 오염 표시되던 문제. 헤딩·주석 직후 한 줄 목적 평문(placeholder) 배치로 재구성. 기존 작업의 이미 생성된 brief는 자동 갱신되지 않음.

### Added
- **KI-4 등록(KNOWN_ISSUES)**: `init.py` update 모드가 `_shared/learnings.md` 로컬 누적분을 덮어씀 — `_local/learnings.md` 병행 기록 완화책 문서화.

## [0.3.2] - 2026-07-04

### Fixed
- **gemini 워커 폴백 실패 사유 유실** — 디스패처(`call_worker.sh`)가 api 폴백의 필수 env
  (`GEMINI_API_KEY`) 부재 시 실패 사유 없이 죽던 문제를 에러 envelope 반환으로 수정,
  호출 시작 시 폴백 불가 사전 경고 추가.

### Changed
- routing.md gemini — 소스·다중파일 검토 인라인 필수(agy 헤드리스 300s 타임아웃 실측),
  폴백 조건(`GEMINI_API_KEY`) 명문화, 시간 제한 작업 전 경량 스모크 권장.

## [0.3.1] - 2026-07-03

### Fixed
- **gemini(agy) 워커 프롬프트 미전달 수정** — Antigravity CLI 1.0.16에서 `-p` 단축 플래그가
  제거되어 backends.json의 `args_template: ["-p", …]`가 프롬프트를 조용히 무시(모델 미호출·사용량 0).
  `["--prompt", …]`로 교정. 증상: gemini 워커가 온보딩 인사만 반환.

## [0.3.0] - 2026-06-28

### Added
- **opt-in goal 요금가드 배선(`--with-guard`)** — 설치 시 `--with-guard`를 주면 `_shared/guard/`에
  워처(`codex_goal_watch.mjs`)와 README가 들어온다. `codex remote-control start`로 공유 데몬을 띄우고
  워처를 실행하면, `/goal` 루프가 주간 사용량 한도에 닿을 때 `app-server proxy`로 활성 goal thread를
  `thread/goal/clear`해 정지시킨다(Codex는 Stop훅으로 못 멈춰 외부 워처 필요). 기본 미설치, 런타임
  on/off=`coach guard on/off`. 정책은 `coach`(usage-coach, codexbar 의존)가 갖고 미설치·조회실패는
  fail-open. 상세=`_shared/guard/README.md`.

## [0.2.0] - 2026-06-10

카파시(Karpathy) 4원칙을 층별로 도입. 기존 규칙과 충돌 없음(보강).

### Added
- **AGENTS.md "Operating Principles" 섹션** — 4원칙 verbatim 차용 + 층별 적용 규칙(Orchestrator 전용 풀버전).
- **`_templates/worker-brief.md` "Worker 행동 규약" 고정 블록** — 워커층 번역형: ②③ 그대로, ①은 가정 명시·표면화(워커는 one-shot이라 사용자 질문 채널 없음), ④는 오케스트레이터 전용.
- **`_templates/worker-result.md` 체크리스트 항목** — "가정·불일치가 Issues/Caveats에 표면화됨".
- **design-basis D7 / system-invariants INV11** — 층별 적용 결정 명문화 + 자가점검.
- **`NOTICE`** — 출처·라이선스 표기 (multica-ai/andrej-karpathy-skills, MIT 선언·LICENSE 파일 부재).

## [0.1.0] - 2026-06-01

multi-agent-starter를 기반으로 Codex Orchestrator 버전을 생성했다.

### Added

- `AGENTS.md`: Codex 세션용 운영 규칙 정본.
- `_shared/routing.md`: `codex-main`, `claude-critic`, `gemini` 기준 worker routing.
- `_shared/approval-policy.md`: worker 승인과 외부/유료 모델 승인 게이트.
- `_shared/orchestrator-rules.md`: Codex 세션 환경 점검, 시스템 수정·검증, 작업 재진입 프로토콜.
- `_shared/design-basis.md`: Codex fork의 결정 기록.
- `_shared/system-invariants.md`: Codex 버전 자가 점검 스크립트.
- `_templates/*`: Codex worker pool 기준 task/context/log/brief/result/task-folder 템플릿.

### Changed

- Orchestrator를 Claude Code 세션에서 Codex 세션으로 변경.
- 리뷰 worker를 Codex 자기검수 구조에서 `claude-critic` 독립 검수 구조로 변경.

### Excluded

- 원본 `.claude/agents/`
- 원본 `_local/learnings.md`
- 원본의 기존 작업 이력 산출물
