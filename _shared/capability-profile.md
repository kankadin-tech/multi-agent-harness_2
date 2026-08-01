# Capability Profile — 슬롯 → 워커 배정 (가변층)

`routing.md`의 decision tree가 정하는 **능력 슬롯을 현재 어떤 워커가 맡는지**의 정본.
신모델 출시·판정 변경 시 **이 파일만 갱신**한다(근거·날짜 필수, 이력 append-only).
모델 식별자 자체의 표기·갱신은 `backends.json`·config 소관(design-basis D7) — 여기서는 배정만 다룬다.

## 현재 배정

| 슬롯 | 담당 워커 | 배정 근거 요약 |
|------|----------|--------------|
| strategist | claude-main (경량은 Orchestrator 직접) | 설계·UI/UX 디자인·전략·문체 우위. **주의**: 워커 핀이 Orchestrator와 같은 모델이면 이 호출로 얻는 것은 모델 다양성이 아니라 컨텍스트 격리 + 독립 2차 패스뿐이다 — 그 값이 승인·쿼터를 쓸 만한지 매번 판단할 것 |
| engineer | codex-main | 대규모 구현·테스트 철저, 비용·속도·토큰 효율 우위 |
| computer-use | codex-main | 브라우저 조작·복잡 워크플로우 수행 우위 |
| reviewer | codex-critic | 교차 벤더 독립 검증 (자기검수 회피) |
| multimodal | gemini | 멀티모달·대용량 문서 처리 |

## 배정 이력 (append-only)

- **2026-07-13** 초기 배정 + computer-use 슬롯 신설. 근거: 외부 리뷰 10건 종합 판정
  (Anthropic 최신 플래그십 vs OpenAI 최신 플래그십) — 디자인·전략·글쓰기 = Claude 우위,
  대규모 구현·테스트·브라우저 조작·비용·속도 = GPT 우위로 수렴. 요지는 design-basis **D12**
  (종전 이 줄과 CHANGELOG 1.3.0이 "D9"로 잘못 인용했다 — D9는 knot 배포 결정이다. 2026-08-01 정정).

- **2026-08-01** 배정 변경 없음. 티어 점검만 수행하고 다음 두 가지를 기록한다.
  ① strategist 워커 핀이 Orchestrator와 동일 모델인 상태 — 배정은 유지하되 위 표에 판단 기준을 명시했다.
  ② 2026-07-13 판정은 그 시점의 플래그십 비교이며, 이후 세대 교체가 반영되지 않았다. **배정을
  바꾸려면 새 판정 자료가 필요하다** — 자료 없이 인상만으로 슬롯을 옮기지 말 것(이 파일의 존재 이유).
  다음 갱신 시 확인할 것: engineer 슬롯을 codex에 둔 근거(대규모 구현·비용·속도 우위)가 현 세대에서도
  유지되는가, reviewer 슬롯의 교차 벤더 독립성이 여전히 확보되는가.

## 갱신 절차

1. 새 판정 자료 확보 (리뷰 종합 · 벤치마크 · 자체 실측)
2. 「현재 배정」 표 갱신 + 「배정 이력」에 날짜·근거 추가 (기존 이력 삭제 금지)
3. 담당명 병기 사본을 **전부** 이 표와 동기화 — `routing.md`(트리 · Worker 역할 상세의 슬롯 표기 · 최소 Worker Set), `CLAUDE.md`(Architecture 워커 풀), `README.md`(Workers 목록), `.claude/agents/claude-main.md`(description·역할). 병기는 편의 사본 — 슬롯 정의는 불변
4. 시스템 구조 파일(orchestrator-rules·invariants 등)은 손대지 않는다
