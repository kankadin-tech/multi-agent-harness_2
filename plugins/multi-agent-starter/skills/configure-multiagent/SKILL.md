---
name: configure-multiagent
description: Use when the user wants to set up / scaffold / install a file-based multi-agent orchestration system in a folder. Triggers on "멀티 에이전트 시스템 구성해줘", "멀티에이전트 세팅", "멀티 에이전트 시스템 만들어줘", "set up a multi-agent system", "configure multi-agent orchestration here". Scaffolds the system (approval gate, task re-entry protocol, topology patterns, invariant self-check) for Claude Code, Codex, or Antigravity via a deterministic generator.
---

# Configure MultiAgent System

이 스킬은 **file-as-memory 멀티에이전트 오케스트레이션 시스템**을 대상 폴더에 생성한다.
**직접 파일을 손으로 쓰지 말 것** — 반드시 이 스킬 폴더에 함께 들어있는 결정적 생성기 `generator/init.py`를 실행한다 (불변식·일관성 보장).

## 절차

1. **flavor 확인** — 사용자에게 묻는다(또는 현재 호스트로 제안):
   - `claude` — Claude Code 오케스트레이터 (워커: claude-main / codex-main / codex-critic / gemini)
   - `codex` — Codex 오케스트레이터 (워커: codex-main / claude-critic / gemini)
   - `antigravity` — Antigravity 오케스트레이터 (Gemini 3.1 Pro High; 워커: claude-main / codex-main / codex-critic, 멀티모달은 오케스트레이터 직접)
2. **대상 폴더 확인** — 어디에 설치할지 묻는다. (상위 폴더 오인 주의 — 정확한 경로를 확인받는다.)
3. **생성기 위치** — `generator/`는 **이 SKILL.md와 같은 폴더 안**에 있다(스킬 자기완결). 호스트별 분기 불필요 — 이 스킬 폴더 기준 `./generator/init.py`. (Claude는 `$CLAUDE_PLUGIN_ROOT/skills/configure-multiagent/generator/init.py`로 해석됨.)
4. **실행** — 확인 후 (이 스킬 폴더의 generator 경로로):
   ```bash
   python3 "<이 스킬 폴더>/generator/init.py" --flavor <claude|codex|antigravity> --target "<대상폴더>" --yes
   ```
   대화형으로 진행하려면 인자 없이 실행하면 메뉴가 뜬다.
5. **결과 보고** — `init.py`가 끝에 `validate.py`를 자동 실행한다. 그 **PASS/FAIL을 그대로 사용자에게 보고**한다. FAIL이 하나라도 있으면 "완료"라고 말하지 말 것.
5-1. **모델 핀 실측 확인 (필수)** — 하네스는 워커를 **최상위 모델로 핀**한다(`_shared/routing.md` 모델 정책). 전체 모델 ID 핀은 그 환경의 availableModels allowlist에 없으면 **경고 없이 부모 모델을 상속**하므로, 설치 직후 1회 실측한다:
   ```bash
   claude --model <claude-main 핀> -p hi --output-format json   # modelUsage 키 = 실제 과금된 모델
   agy models                                                   # gemini 핀이 가용·최신인지 대조
   ```
   핀에 접근권이 없으면 그 환경에서 쓸 수 있는 최상위 모델로 낮추고, 사용자에게 무엇을 낮췄는지 보고한다. codex 워커는 `~/.codex/config.toml`이 정본이라 여기서 강제할 수 없으므로 **현재 `model`·`model_reasoning_effort` 값을 사용자에게 알려** 최상위인지 확인받는다.
5-2. **`safety-guide` 스킬 실행 (필수)** — 최상위 모델은 광범위한 안전장치를 갖고 있어, 그 오탐이 워커의 실제 실행 모델을 조용히 바꿀 수 있다. 설치 직후 **`safety-guide` 스킬을 실행**해 대상 환경에 맞는 마찰 완화 가이드를 세팅한다.
   - 그 스킬 자체의 판단 기준(§0 게이트)을 존중한다 — 스킬이 "이 repo는 스킵" 판정을 내리면 그 판정을 따르고, **판정 결과를 사용자에게 보고**한다(무시하고 강행하지 말 것).
   - 스킬이 설치돼 있지 않은 환경이면 "미설치라 건너뜀"을 명시적으로 보고한다. 가이드 본문을 손으로 창작하지 말 것.
5-3. **goal 요금가드 배선 확인 (필수)** — 하네스는 워커를 최상위 모델로 돌리므로 사용량이 몰린다. 설치 직후 가드가 실제로 걸려 있는지 확인한다:
   ```bash
   command -v coach                                        # ① coach 바이너리 존재?
   grep -ls 'coach --hook' ~/.claude/settings.json "<대상폴더>/.claude/settings.json"  # ② Stop 훅 배선?
   ```
   - ②는 **전역 `~/.claude/settings.json` 또는 대상 폴더 `.claude/settings.json`** 둘 중 하나에 있으면 된다. **전역 배선이 이미 있으면 폴더별 재설치는 불필요**하다 — 중복 배선하지 말 것.
   - 배선이 없으면 **loadout 카탈로그**(https://github.com/netwaif/loadout)의 **guard 품목**으로 설치한다(codex flavor는 `--flavor codex`로 워처를 `_shared/guard/`에 복사한다).
   - loadout이 없는 환경이면 **그 사실과 전제**(usage-coach https://github.com/netwaif/usage-coach + codexbar)를 사용자에게 보고하고 넘어간다. **가이드 본문이나 훅을 손으로 창작하지 말 것** — 가드 자산의 정본은 loadout이다.
   - 특성: **fail-open**(coach가 없거나 사용량 조회가 실패해도 작업을 죽이지 않는다), 런타임 스위치 `coach guard on|off|status`.
6. **knot 안내(선택)** — 사용자가 knot 지식 vault를 찾으면 알린다: 설치는 v3.0.0부터 **loadout 카탈로그**(https://github.com/netwaif/loadout) 담당이다("CLAUDE.md 구성 골라 담아줘"). `knot` 능동 스킬(save/ingest/query/lint)은 v3.1.0부터 knot 자체 플러그인이 배포한다(마켓플레이스에 `netwaif/knot` 추가). goal 요금가드는 위 **5-3** 참조(가드 배선 자산도 v3.2.0부터 loadout guard 품목이 전부 제공한다).

## 동작 보장

- **결정적**: 번들 템플릿을 그대로 복사. 모델이 시스템 파일을 창작하지 않는다.
- **안전**: 대상에 기존 `tasks/`·`_local/` 사용자 데이터가 있으면 보존(update 모드).
- **쓰기 권한**: 파일 생성이므로 쓰기 권한이 필요하다. Codex에서는 `workspace-write` + 승인이 필요할 수 있다 — 막히면 사용자에게 권한을 안내한다.

## Do NOT

- 시스템 파일(CLAUDE.md/AGENTS.md, `_shared/*`, `_templates/*`)을 직접 작성·수정하지 말 것. 항상 `init.py`로 생성.
- 플러그인 자신의 폴더나 `generator/templates/`(이 스킬 폴더 안) 안에 설치하지 말 것 (init.py가 막지만 시도도 금지).
- validate FAIL을 숨기거나 "대충 됐다"고 보고하지 말 것.
