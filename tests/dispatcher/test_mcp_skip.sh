#!/usr/bin/env bash
# S7: primary가 mcp/native(디스패처가 실행할 수 없는 타입)일 때의 동작.
# 2026-08-01 이전에는 서브셸 die가 빈 문자열을 남겨, 폴백이 있으면 "조용한 대체 실행",
# 폴백이 없으면 호출부 jq 크래시(exit 2, envelope 없음)로 끝났다. 그 회귀를 잠근다.
. "$(dirname "$0")/_lib.sh"
echo "S7 디스패처 mcp/native primary 건너뜀"

# (1) 폴백 있음 → 건너뛴 사실이 envelope에 남고 폴백이 정상 실행돼야
ROOT="$(new_root <<'JSON'
{"schema_version":"1","flavor":"claude","workers":{"t":{
  "call_type":"mcp","model":"primary","approval_class":"worker","result_capture":"tool-return",
  "timeout":10,"brief_mode":"path","mcp":{"tool":"mcp__x__y","args_template":{}},
  "fallbacks":[{"call_type":"cli","model":"fb","approval_class":"worker","result_capture":"stdout",
    "timeout":10,"brief_mode":"path","cli":{"command":"claude","args_template":["-p","@brief"]}}]}}}
JSON
)"
echo "brief" > "$ROOT/brief.txt"
fake_bin "$ROOT" claude 0

dispatch "$ROOT" t "$ROOT/brief.txt"
assert_eq "폴백 있음 → exit 0"        0     "$RC"
assert_eq "skipped_primary=mcp 기록"  mcp   "$(jq -r '.skipped_primary // "없음"' <<<"$OUT")"
assert_eq "폴백 모델로 실행"           fb    "$(jq -r '.model' <<<"$OUT")"
rm -rf "$ROOT"

# (2) 폴백 없음 → jq 크래시가 아니라 유효 envelope + exit 1
ROOT="$(new_root <<'JSON'
{"schema_version":"1","flavor":"claude","workers":{"t":{
  "call_type":"mcp","model":"primary","approval_class":"worker","result_capture":"tool-return",
  "timeout":10,"brief_mode":"path","mcp":{"tool":"mcp__x__y","args_template":{}}}}}
JSON
)"
echo "brief" > "$ROOT/brief.txt"

dispatch "$ROOT" t "$ROOT/brief.txt"
assert_eq "폴백 없음 → exit 1"        1      "$RC"
assert_eq "유효 envelope (구 jq 크래시)" ok    "$(printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 && echo ok || echo broken)"
assert_eq "status=error"              error  "$(jq -r '.status' <<<"$OUT")"
assert_eq "fallback_used=false"       false  "$(jq -r '.fallback_used' <<<"$OUT")"
rm -rf "$ROOT"

finish
