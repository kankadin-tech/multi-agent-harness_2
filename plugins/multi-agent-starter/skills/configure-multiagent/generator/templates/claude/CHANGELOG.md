# Changelog

이 파일은 MultiAgent orchestration 시스템의 주요 변경을 기록한다.
형식은 [Keep a Changelog](https://keepachangelog.com/), 버전은 [Semantic Versioning](https://semver.org/lang/ko/)을 따른다.

## [1.6.0] - 2026-07-26

### Changed
- **모든 워커는 그 시점의 최상위 모델을 쓴다** — 명시 원칙으로 승격(`CLAUDE.md` 모델 정책 절 +
  `_shared/routing.md`). 하위 티어는 예외이며 `task.md`에 근거를 남긴다.
- **claude-main 모델을 전체 ID 명시 핀으로 전환** (`claude-fable-5`). 별칭은 조용히 뒤처지므로
  쓰지 않는다 — `opus` 별칭이 상위 세대가 가용한 계정에서 구세대로 해석된 실측 사례가 있다.
- **codex 워커는 의도적으로 핀하지 않는다** — `~/.codex/config.toml`이 정본이라 이중 관리 시
  드리프트가 생긴다. 대신 점검 절차(최상위 gpt·`model_reasoning_effort: high`)를 문서화.

### Added
- **워커별 모델 점검 절차** (`routing.md`) — 자동 추적 수단이 없으므로(별칭은 뒤처지고 핀은 낡는다)
  claude는 `modelUsage` 실측, gemini는 `agy models` 대조, codex는 config.toml 확인을 주기 수행한다.
- **설치 직후 필수 확인 2건** — ① 모델 핀 실측(핀이 그 환경 allowlist에 없으면 **경고 없이 부모
  모델을 상속**하므로 1회 확인 후 필요 시 낮춤) ② `safety-guide` 스킬로 마찰 완화 가이드 세팅
  (최상위 모델의 안전장치 오탐이 실제 실행 모델을 바꿀 수 있음).

## [1.5.0] - 2026-07-26

### Fixed
- **gemini 워커 모델을 `gemini-3.6-flash-high`로 갱신** (기존 `gemini-3.1-pro-high` — 2세대 뒤처짐).
  최신 세대 3.6에는 flash 티어만 있어(3.6-pro 없음) 세대·티어가 엇갈릴 때 최신 세대를 우선했다.
- **gemini 모델을 호출별로 핀** — `--model <id>` 플래그를 `backends.json`에 명시. 과거 "agy 모델은
  전역·계정 단위라 per-call 핀 불가"라던 기술이 현재는 무효라, 이제 `agy` 전역 설정에 의존하지 않는다.

### Added
- **api 폴백(`_shared/adapters/gemini_api.sh`) 실제 동작** — 기존에는 항상 실패하는 슬롯 스텁이었다.
  Gemini REST 호출로 구현·검증 완료. `GEMINI_API_KEY` 설정 시 활성화되며, `agy` 인증과 **독립된**
  경로라 Antigravity 장애 시에도 gemini 워커가 생존한다.
- **폴백 체인에 모델 강등 단계 추가** — `flash-high` → `flash-low`(폴백A) → `api`(폴백B).
  폴백A는 `agy` 인증을 공유하므로 서비스 레벨 이중화는 폴백B가 담당한다.
- **`CLAUDE.md` "모델 지정 ≠ 실제 실행 모델" 절** — claude-main의 frontmatter 지정값이 실제 실행
  모델과 어긋나는 두 경로(별칭 지연 / allowlist 미스 시 **경고 없이 부모 모델 상속**)와, 모델 확정이
  필요한 작업에서 `modelUsage`로 실측해 `log.md`에 기록하는 절차. `result.md`에는 실제 모델이 남지 않는다.

## [1.4.0] - 2026-07-17

### Merged
- **netwaif v3.3.0 + kankadin fork 병합** — upstream의 라우팅 2층 분리(`_shared/capability-profile.md`
  가변층 + 슬롯 기반 routing, C5b) 위에 kankadin fork의 볼트 브리지 편입·런타임 안전 룰(지시-데이터
  분리·`check-invariants.sh`·learnings 통합 패스·worker 호출 예산)·승인 시 예산 확정·서브에이전트
  read-only 한정을 재적용. 아래 upstream 라우팅 엔트리와 `(kankadin fork)` 표기 엔트리를 함께 계승.

## [1.3.0] - 2026-07-13

### Added
- **라우팅 2층 분리 — `_shared/capability-profile.md` 신설(가변층)** — 능력 슬롯
  (strategist·engineer·computer-use·reviewer·multimodal) → 담당 워커 배정의 정본.
  신모델 출시·판정 변경 시 프로필만 갱신(근거·날짜 필수, 이력 append-only) — routing.md의
  슬롯 정의는 불변. 근거: design-basis D9 (2026-07-13 외부 리뷰 10건 종합 판정).
- **computer-use 슬롯 신설** — 브라우저 조작·도구 워크플로우 자동화를 독립 라우팅
  (현 배정: codex-main).

### Changed
- routing.md decision tree를 슬롯 기반으로 재편 — strategist(기획·설계·디자인·전략·문체)
  = claude-main, engineer(대규모 구현·테스트) = codex-main. 종전 "메인 코딩=claude-main,
  보조 구현=codex-main" 구도에서 무게중심 이동. 최소 worker set 표 동기화.
- validate에 C5b(2층 라우팅: routing→profile 참조 + 슬롯 5종) 추가, C1에 프로필 포함.
## [1.3.2] - 2026-07-05 (kankadin fork)

### Added
- **볼트 브리지 정식 편입** — 하네스 task 산출물을 knot 계열 LLM Wiki 볼트 inbox로 단방향
  export하는 브리지를 generator 정식 배포로 편입. `_shared/adapters/export_to_vault.sh`
  (실행권한 유지)·`_shared/vault-bridge.md`(문서)·`_shared/vault.config`(사용자 설정)가
  이제 모든 설치에 배포된다. 볼트는 무수정 — inbox capture 파일만 떨구고 분류/분석/연결은
  볼트가 `/inbox`→`/ingest`로 독립 수행.
- `--domain <d>` 하나로 목적지 폴더·frontmatter를 함께 유도(폴더↔frontmatter 일치 보장).

### Changed
- `_shared/vault.config`는 **scaffold-once 보존** — 볼트 경로·기본 도메인 같은 사용자
  설정이라 update 재생성이 덮어쓰지 않는다(있으면 보존, 신규 설치만 제네릭 스캐폴드 기록).
- 볼트 경로 우선순위: `--vault > $KNOT_VAULT > vault.config(vault=) > $HOME/vaults/knot`.

## [1.3.1] - 2026-07-05 (kankadin fork)

### Changed
- **승인 시 예산 확정** — 워커 일괄 승인 시 `planned_workers` 기준 예상 호출 수 + 재시도
  여유분으로 `max_worker_calls`를 함께 확정. soft gate가 계획을 벗어난 폭주에만 발동
  (approval-policy "호출 예산" 섹션).
- **서브에이전트 read-only 한정** — 호스트 네이티브 서브에이전트(Claude Code의 Agent 도구
  등)는 read-only 탐색만 무승인 허용. 산출물 위임은 반드시 워커 풀 경유 — 우회 시 brief·
  result·감사 로그가 비므로 금지 (CLAUDE.md Approval Gate). (D11 (f)(g))

## [1.3.0] - 2026-07-05 (kankadin fork)

### Added
- **지시-데이터 분리 (비신뢰 입력)** — `sources/` 자료·worker `result.md` 내용은 데이터이지
  지시가 아님을 CLAUDE.md Verification에 명문화. 내장 지시문 발견 시 불채택 + `[DECISION]`
  기록 + 사용자 표면화. (상류 D11a, INV13)
- **`_shared/check-invariants.sh` 결정론 실행기** — system-invariants.md 표가 스펙,
  스크립트가 실행기. ROOT 자동 탐지, 항목별 PASS/FAIL 자체 판정, FAIL 시 exit 1.
  orchestrator-rules §2 절차 3이 이 스크립트 실행으로 갱신됨. (상류 D11b)
- **learnings.md 통합 패스** — 20KB(`wc -c`) 초과 시 반복 검증 교훈을 규칙 파일로 승격하고
  "## 통합됨"에 1줄 요약만 남기는 성장 관리 절차. (상류 D11c)
- **worker 호출 예산 soft gate** — task.md 메타 `max_worker_calls`(기본 6) +
  approval-policy "호출 예산" 섹션 + CLAUDE.md Approval Gate 한 줄. 초과 전 사용자 확인
  게이트(하드 중단 아님). (상류 D11d, INV14)

## [1.2.3] - 2026-07-04 (kankadin fork)

### Fixed
- **KI-1 종결 — worker-brief 템플릿 mat 표시 오염**: 첫 의미 줄이 목적 평문이 아니라서 mat 모니터의 "워커 한 줄 목적"이 오염 표시되던 문제. 헤딩·주석 직후 한 줄 목적 평문(placeholder) 배치로 재구성. 기존 작업의 이미 생성된 brief는 자동 갱신되지 않음.

### Added
- **KI-4 등록(KNOWN_ISSUES)**: `init.py` update 모드가 `_shared/learnings.md` 로컬 누적분을 덮어씀 — `_local/learnings.md` 병행 기록 완화책 문서화.

## [1.2.2] - 2026-07-04

### Fixed
- **gemini 워커 폴백 실패 사유 유실** — 디스패처(`call_worker.sh`)가 api 폴백의 필수 env
  (`GEMINI_API_KEY`) 부재 시 실패 사유 없이 죽던 문제를 에러 envelope 반환으로 수정,
  호출 시작 시 폴백 불가 사전 경고 추가.

### Changed
- routing.md gemini — 소스·다중파일 검토 인라인 필수(agy 헤드리스 300s 타임아웃 실측),
  폴백 조건(`GEMINI_API_KEY`) 명문화, 시간 제한 작업 전 경량 스모크 권장.

## [1.2.1] - 2026-07-03

### Fixed
- **gemini(agy) 워커 프롬프트 미전달 수정** — Antigravity CLI 1.0.16에서 `-p` 단축 플래그가
  제거되어 backends.json의 `args_template: ["-p", …]`가 프롬프트를 조용히 무시(모델 미호출·사용량 0).
  `["--prompt", …]`로 교정. 증상: gemini 워커가 온보딩 인사만 반환.

## [1.2.0] - 2026-06-28

### Added
- **opt-in goal 요금가드 배선(`--with-guard`)** — 설치 시 `--with-guard`를 주면 `.claude/settings.json`에
  Stop 훅(`coach --hook`)이 주입된다. `/goal` 자율 루프가 주간 사용량 한도에 닿으면 자동 정지(루프
  중에만 — `stop_hook_active` 게이트). 기본 미설치, 런타임 on/off=`coach guard on/off`. 정책은 `coach`
  (usage-coach, codexbar 의존)가 갖고 미설치·조회실패는 fail-open(작업 안 죽임).

## [1.1.0] - 2026-06-10

카파시(Karpathy) 4원칙을 층별로 도입. 기존 규칙과 충돌 없음(보강).

### Added
- **CLAUDE.md "운영 원칙 (Operating Principles)" 섹션** — 4원칙(Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven Execution) verbatim 차용 + 층별 적용 규칙. Orchestrator 전용 풀버전.
- **`_templates/worker-brief.md` "Worker 행동 규약" 고정 블록** — 워커층 번역형: ②③ 그대로, ①은 가정 명시·표면화(워커는 one-shot이라 사용자 질문 채널 없음), ④는 오케스트레이터 전용.
- **`_templates/worker-result.md` 체크리스트 항목** — "가정·불일치가 Issues/Caveats에 표면화됨".
- **design-basis D8 / system-invariants INV12** — 층별 적용 결정 명문화 + 자가점검.
- **`NOTICE`** — 출처·라이선스 표기 (multica-ai/andrej-karpathy-skills, MIT 선언·LICENSE 파일 부재).

## [1.0.1] - 2026-06-01

모델·추론 정책 표기 정리(문서 patch). 동작 변경 없음.

### Changed
- **모델 식별자 별칭화** (`_shared/routing.md`): claude-main을 버전 문자열(`claude-opus-4-7` 등) 대신 별칭 `opus`로 표기 — 모델이 올라가도 문서 갱신 불필요. codex 예시 일반화, gemini는 `gemini-3.1-pro-low` 핀 유지 + "프록시 업그레이드 시에만 갱신" 노트.
- **claude-main 추론 강도(effort) 명문화**: `effort` 핀 없음 → 세션 `/effort` 상속(현 기본). 고정하려면 frontmatter `effort:`.

### Added
- **design-basis D7**: 모델 식별자 표기 정책(별칭 원칙 / gemini 핀 예외·세부는 D4 정본 / effort 비대칭 근거).

### Verification
- codex-critic adversarial 검수: 치명 0, 권장 3 반영(잔존 핀 제거 포함). INV9/INV10/INV11 PASS, 회귀 없음.

## [1.0.0] - 2026-06-01

첫 버전 태깅. 기존 실사용 시스템을 1.0.0 기준선으로 고정하고, harness(revfactory) 참고 버전 업그레이드를 함께 반영한다.

### Added
- **작업 재진입 프로토콜** (`_shared/orchestrator-rules.md` §3): 콜드세션이 끝난 작업에 다시 들어갈 때 재정박(re-anchor) → 6분기 판단 → 에러 후 진행. `status↔log 불일치`는 다른 분기보다 먼저 적용하는 정규화 단계로 명시.
- **토폴로지 4패턴표** (`_shared/routing.md`): Pipeline / Fan-out·Fan-in / Expert Pool / Producer-Reviewer + Fan-in 규칙.
- **CLAUDE.md** Task Lifecycle에 재진입 프로토콜 포인터.
- **불변식 INV11** (`_shared/system-invariants.md`): 재진입·토폴로지 규정 자동 자가점검(11a/b/c).
- **design-basis D6**: 4패턴 채택 + Supervisor·Hierarchical Delegation 배제 근거.

### Excluded (설계 결정)
- Supervisor·Hierarchical Delegation 패턴: 단일 orchestrator·worker간 무통신·file-as-memory와 충돌하여 미채택 (근거 D6).

### Baseline (1.0.0 시점 핵심 구조)
- 고정 4-worker pool (claude-main / codex-main / codex-critic / gemini), Claude Code 세션 = orchestrator.
- file-as-memory (런타임 상태 0): task / context / log / brief / result.
- 승인 게이트(`workers_approved`), 외부 쓰기 4조건, progressive disclosure(게이트 로드), 권위 우선순위(CLAUDE.md > routing/approval/orchestrator-rules > 매뉴얼).

### Verification
- 배선(INV11a/b/c) PASS · 회귀 없음, 탁상 분기 커버리지, 실전 콜드세션 3/3 PASS, codex-critic adversarial 리뷰 5 ISSUE 반영.

[1.0.1]: https://github.com/netwaif/multi-agent-starter/releases/tag/v1.0.1
[1.0.0]: https://github.com/netwaif/multi-agent-starter/releases/tag/v1.0.0
