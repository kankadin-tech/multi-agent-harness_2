#!/usr/bin/env bash
# A6: 디스패처 입력 가드 — usage / brief '..' / 미정의 role / allowlist 밖 명령.
. "$(dirname "$0")/_lib.sh"
echo "A6 디스패처 가드"

# usage (인자 없음) → exit 64  (run_backend 이전 단계)
bash "$DISPATCHER" >/dev/null 2>&1
assert_eq "인자 없음 → exit 64" 64 "$?"

ROOT="$(new_root <<'JSON'
{"schema_version":"1","flavor":"claude","workers":{
  "t":{"call_type":"cli","model":"m","approval_class":"worker","result_capture":"stdout",
       "timeout":5,"brief_mode":"path","cli":{"command":"agy","args_template":["@brief"]}},
  "bad":{"call_type":"cli","model":"m","approval_class":"worker","result_capture":"stdout",
       "timeout":5,"brief_mode":"path","cli":{"command":"rm","args_template":["-rf","@brief"]}}}}
JSON
)"
echo "brief" > "$ROOT/brief.txt"

# brief 경로에 '..' → exit 6
dispatch "$ROOT" t "$ROOT/../x"
assert_eq "brief '..' → exit 6" 6 "$RC"

# 미정의 role → exit 2
dispatch "$ROOT" nope "$ROOT/brief.txt"
assert_eq "미정의 role → exit 2" 2 "$RC"

# allowlist 밖 명령(rm) → 실행 안 됨(거부), stderr에 allowlist 언급.
# 구 러프엣지 T2(폴백 없는 die → 빈 envelope → 호출부 jq 크래시 exit 2)는 2026-08-01 종결:
# 이제 모든 거부 경로가 유효 envelope를 낸다. 아래 두 단언이 그 회귀를 잠근다.
dispatch "$ROOT" bad "$ROOT/brief.txt"
assert_eq       "allowlist 위반 → exit 비0"  nonzero   "$([ "$RC" -ne 0 ] && echo nonzero || echo zero)"
assert_contains "stderr에 allowlist"        allowlist "$ERR"
assert_eq       "거부도 유효 envelope"        ok        "$(printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 && echo ok || echo broken)"
assert_eq       "거부 envelope status=error" error     "$(printf '%s' "$OUT" | jq -r '.status' 2>/dev/null)"

rm -rf "$ROOT"
finish
