#!/usr/bin/env bash
# gemini_api.sh — gemini worker의 API 폴백(독립 인증 경로 = 진짜 이중화 슬롯).
# 사용: gemini_api.sh <brief-file>   (call_worker.sh가 api 폴백 시 호출)
# stdout = 모델 응답 텍스트, exit 0=성공.
#
# 존재 이유: cli 1차·폴백A는 둘 다 Antigravity(agy) 인증에 의존한다. Antigravity 자체
# 장애 시 함께 죽으므로, 서비스-레벨 이중화는 별도 인증(API 키)뿐이다.
# (homebrew gemini CLI 경로는 Google이 free-tier 클라이언트 지원을 종료 —
#  IneligibleTierError: "migrate to the Antigravity suite" — 이라 폴백으로 쓸 수 없다.)
#
# 활성 조건: GEMINI_API_KEY(Google AI Studio 발급) 설정.
#   미설정이면 call_worker.sh의 required_env 사전점검에서 걸러지므로 이 스크립트는 실행되지 않는다.
# 모델: GEMINI_API_MODEL 로 오버라이드. 기본 `gemini-flash-latest` = 벤더가 최신 flash로
#   갱신하는 별칭이라 자동 추적된다. 가용 목록 확인:
#     curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY" \
#       | jq -r '.models[].name'
#
# 상태: 검증 완료(2026-07-26) — 키 설정 후 실호출 exit 0, 응답 정상 반향 확인.
#   당시 `gemini-flash-latest`·`gemini-pro-latest` 별칭 존재 확인(모델 50개 가용).
set -euo pipefail

BRIEF="${1:?usage: gemini_api.sh <brief-file>}"
[ -f "$BRIEF" ] || { echo "gemini_api: brief 없음: $BRIEF" >&2; exit 6; }
: "${GEMINI_API_KEY:?gemini_api: GEMINI_API_KEY 필요}"

MODEL="${GEMINI_API_MODEL:-gemini-flash-latest}"
ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"

command -v jq >/dev/null 2>&1 || { echo "gemini_api: jq 필요" >&2; exit 7; }

payload="$(jq -n --rawfile b "$BRIEF" '{contents:[{parts:[{text:$b}]}]}')"

# body + HTTP code 분리 수집(--fail-with-body 미지원 curl 대비 이식성).
raw="$(curl -sS -X POST "$ENDPOINT" \
        -H "x-goog-api-key: ${GEMINI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        -w $'\n%{http_code}')" || { echo "gemini_api: curl 실패" >&2; exit 4; }

code="$(printf '%s' "$raw" | tail -n1)"
body="$(printf '%s' "$raw" | sed '$d')"

if [ "$code" != "200" ]; then
  # 키 값은 절대 로그에 남기지 않는다(에러 본문만).
  echo "gemini_api: HTTP ${code} (model=${MODEL}): $(printf '%s' "$body" | head -c 500)" >&2
  exit 4
fi

text="$(printf '%s' "$body" | jq -r '[.candidates[0].content.parts[]?.text] | join("")' 2>/dev/null || true)"
if [ -z "$text" ] || [ "$text" = "null" ]; then
  echo "gemini_api: 응답 파싱 실패(model=${MODEL}): $(printf '%s' "$body" | head -c 500)" >&2
  exit 4
fi

printf '%s\n' "$text"
