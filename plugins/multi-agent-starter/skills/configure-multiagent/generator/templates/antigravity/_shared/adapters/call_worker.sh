#!/usr/bin/env bash
# call_worker.sh — backends.json 디스패처 (cli/api 전용).
# native/mcp는 오케스트레이터가 직접 호출(디스패처 비경유).
# 사용: call_worker.sh <role> <brief-file>
# 반환: stdout에 result envelope(JSON). exit 0=성공, 비0=실패/거부.
set -euo pipefail

# ── 임시자원 추적 + 강제 정리(die·인터럽트·정상 모두) ──
_TMPS=()
cleanup() { local p; for p in "${_TMPS[@]:-}"; do [ -n "$p" ] && rm -rf -- "$p"; done; return 0; }  # 항상 0: EXIT trap이 종료코드 덮어쓰지 않도록
trap cleanup EXIT INT TERM
mktmp()  { local t; t="$(mktemp)";    _TMPS+=("$t"); printf '%s' "$t"; }
mktmpd() { local t; t="$(mktemp -d)"; _TMPS+=("$t"); printf '%s' "$t"; }

die() { echo "call_worker: $1" >&2; exit "${2:-1}"; }

ROLE="${1:-}"; BRIEF="${2:-}"
[ -n "$ROLE" ] && [ -n "$BRIEF" ] || die "usage: call_worker.sh <role> <brief-file>" 64

SCRIPT_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${MULTIAGENT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BACKENDS="$ROOT/_shared/backends.json"

command -v jq >/dev/null 2>&1 || die "jq 필요(JSON 파싱)" 5
[ -f "$BACKENDS" ] || die "backends.json 없음: $BACKENDS" 5

# timeout: coreutils timeout/gtimeout 우선, 없으면 portable bash 폴백(둘 다 유한 보장)
TIMEOUT_BIN=""
command -v timeout  >/dev/null 2>&1 && TIMEOUT_BIN=timeout
[ -z "$TIMEOUT_BIN" ] && command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN=gtimeout
run_limited() {  # run_limited <secs> -- <cmd...>
  local t="$1"; shift; [ "$1" = "--" ] && shift
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" -k 5 "$t" "$@"; return $?; fi
  # 폴백: python3 러너(결정적, 프로세스그룹 TERM→KILL). python3은 시스템 필수 의존성.
  command -v python3 >/dev/null 2>&1 || die "timeout 유틸 또는 python3 필요" 5
  python3 "$SCRIPT_DIR/_run.py" "$t" "$@"; return $?
}

# brief 절대경로화 + 검증 ('--'로 옵션 하이재킹 방어)
case "$BRIEF" in *..*) die "brief 경로에 '..' 금지" 6;; esac
[ -f "$BRIEF" ] || die "brief 파일 없음: $BRIEF" 6
BRIEF="$(cd "$(dirname -- "$BRIEF")" && pwd)/$(basename -- "$BRIEF")"

rec="$(jq -c --arg r "$ROLE" '.workers[$r] // empty' "$BACKENDS")"
[ -n "$rec" ] || die "role 미정의: $ROLE" 2

# ── 승인 게이트(기계적 강제) ──
# 종전엔 workers_approved·max_worker_calls가 문서 규약뿐이라 셸에서 직접 실행하면
# 무승인 호출이 그대로 나갔다. 판정 정본은 _shared/hooks/approval_gate.py.
GATE="$ROOT/_shared/hooks/approval_gate.py"
if [ "${MULTIAGENT_SKIP_APPROVAL_GATE:-0}" = "1" ]; then
  echo "call_worker: 경고 — 승인 게이트를 우회했습니다(MULTIAGENT_SKIP_APPROVAL_GATE=1)." >&2
elif [ -f "$GATE" ] && command -v python3 >/dev/null 2>&1; then
  grc=0; python3 "$GATE" --role "$ROLE" --brief "$BRIEF" >&2 || grc=$?
  [ "$grc" -eq 0 ] || die "승인 게이트가 이 호출을 거부했습니다(사유는 위)." 9
fi

# 폴백 가용성 사전 점검(경고만): primary가 죽고 나서야 폴백 불가를 아는 것을 방지
while IFS= read -r _fe; do
  [ -n "$_fe" ] && [ -z "${!_fe:-}" ] && \
    echo "call_worker: 경고 — 폴백 필수 env 미설정: $_fe (primary 실패 시 폴백 불가)" >&2
done < <(jq -r '.fallbacks[]?.api.required_env[]? // empty' <<<"$rec")

redact() { sed -E 's/[A-Za-z0-9_-]{32,}/[REDACTED]/g'; }

# 실패도 반드시 유효한 envelope로 낸다 — run_backend는 어떤 경로로 빠져나가도
# stdout에 파싱 가능한 JSON을 남겨야 한다(호출부가 --argjson으로 받으므로 빈 문자열이면 크래시).
err_envelope() {  # err_envelope <exit_code> <backend> <model> <msg>
  jq -n --argjson exit "$1" --arg backend "$2" --arg model "$3" --arg msg "$4" \
    '{status:"error", exit_code:$exit, backend:$backend, model:$model,
      duration_s:0, stdout:"", stderr_sanitized:$msg}'
}

# brief 경로에서 작업 폴더 유도: tasks/<task>/workers/<role>/brief.md → tasks/<task>
# 못 찾으면 ROOT(종전 동작)로 폴백.
task_dir_from_brief() {
  local d; d="$(dirname -- "$BRIEF")"
  while [ "$d" != "/" ]; do
    if [ "$(basename -- "$(dirname -- "$d")")" = "tasks" ]; then printf '%s' "$d"; return 0; fi
    d="$(dirname -- "$d")"
  done
  printf '%s' "$ROOT"
}

# 단일 backend 실행 → envelope(JSON)을 stdout, exit code 반환
run_backend() {
  local spec="$1" ctype bmode tmo cwdp model wd out err errd rc start dur
  ctype="$(jq -r '.call_type' <<<"$spec")"
  model="$(jq -r '.model // "?"' <<<"$spec")"
  case "$ctype" in
    # 디스패처는 bash라 MCP 도구·호스트 서브에이전트를 실행할 수 없다. die로 죽이면
    # 명령치환 서브셸만 죽어 빈 문자열이 남고 호출부 jq가 크래시했다. 건너뜀을
    # envelope에 남기고 3을 반환해 cli/api 폴백으로 이어지게 한다.
    native|mcp)
      err_envelope 3 "$ctype" "$model" \
        "call_type=$ctype는 디스패처가 실행하지 않는다(오케스트레이터가 직접 호출). 이 항목은 건너뛴다."
      return 3 ;;
    cli|api) ;;
    *) err_envelope 7 "$ctype" "$model" "잘못된 call_type: $ctype"; return 7 ;;
  esac
  bmode="$(jq -r '.brief_mode // "content"' <<<"$spec")"
  tmo="$(jq -r '.timeout // 300' <<<"$spec")"
  cwdp="$(jq -r '.cwd_policy // "repo_root"' <<<"$spec")"

  case "$cwdp" in
    isolated_tmp) wd="$(mktmpd)";;
    target)       wd="${TARGET_REPO:-$ROOT}";;
    task_dir)     wd="$(task_dir_from_brief)";;
    *)            wd="$ROOT";;
  esac

  local -a cmd=()
  if [ "$ctype" = "cli" ]; then
    local command_bin args_json a
    command_bin="$(jq -r '.cli.command' <<<"$spec")"
    case "$command_bin" in agy|codex|claude) ;;
      *) err_envelope 7 "$ctype" "$model" "command allowlist 위반: $command_bin"; return 7;; esac
    cmd+=("$command_bin")
    args_json="$(jq -r '.cli.args_template[]' <<<"$spec")"   # jq 실패 시 set -e 트리거
    while IFS= read -r a; do
      case "$a" in
        "@brief")         cmd+=("$BRIEF");;
        "@brief_content") cmd+=("$(cat -- "$BRIEF")");;
        *)                cmd+=("$a");;
      esac
    done <<<"$args_json"
    # codex 워커: 기본은 git 요구(안전망). git 없으면 명확히 실패. 옵트아웃 시에만 우회.
    if [ "$command_bin" = "codex" ]; then
      if [ "${MULTIAGENT_CODEX_SKIP_GIT:-0}" = "1" ]; then
        local -a _nc=(); local _ins=0 _x
        for _x in "${cmd[@]}"; do
          _nc+=("$_x")
          if [ "$_ins" = 0 ] && [ "$_x" = "exec" ]; then _nc+=("--skip-git-repo-check"); _ins=1; fi
        done
        cmd=("${_nc[@]}")
      elif ! command -v git >/dev/null 2>&1; then
        err_envelope 8 "$ctype" "$model" \
          "codex 워커는 git이 필요합니다. git 설치 후 재시도하거나, 위험을 감수하면 MULTIAGENT_CODEX_SKIP_GIT=1 로 우회하세요."
        return 8
      fi
    fi
  else
    local ref reqenv brief_pass
    ref="$(jq -r '.api.ref' <<<"$spec")"
    case "$ref" in adapters/*) ;;
      *) err_envelope 7 "$ctype" "$model" "api.ref는 adapters/ 내부만"; return 7;; esac
    case "$ref" in *..*)
      err_envelope 7 "$ctype" "$model" "api.ref에 '..' 금지"; return 7;; esac
    if [ ! -f "$ROOT/_shared/$ref" ]; then
      err_envelope 4 "$ctype" "$model" "api 스크립트 없음: $ref"; return 4
    fi
    while IFS= read -r reqenv; do
      [ -n "$reqenv" ] || continue
      if [ -z "${!reqenv:-}" ]; then
        # die 대신 에러 envelope 반환: 폴백 체인에서 실패 사유가 최종 envelope에 남도록
        jq -n --arg model "$model" --arg e "$reqenv" \
          '{status:"error", exit_code:4, backend:"api", model:$model,
            duration_s:0, stdout:"", stderr_sanitized:("필수 env 없음: " + $e + " — 폴백 사용 불가")}'
        return 4
      fi
    done < <(jq -r '.api.required_env[]? // empty' <<<"$spec")
    brief_pass="$(jq -r '.api.brief_pass // "arg1"' <<<"$spec")"
    cmd+=("bash" "$ROOT/_shared/$ref")
    [ "$brief_pass" = "arg1" ] && cmd+=("$BRIEF")
    [ "$brief_pass" = "stdin" ] && bmode="stdin"
  fi

  out="$(mktmp)"; err="$(mktmp)"; errd="$(mktmp)"
  start=$(date +%s)
  rc=0
  (
    cd "$wd" || exit 70
    export CI=1 DEBIAN_FRONTEND=noninteractive
    if [ "$bmode" = "stdin" ]; then
      run_limited "$tmo" -- "${cmd[@]}" <"$BRIEF"
    else
      run_limited "$tmo" -- "${cmd[@]}" </dev/null
    fi
  ) >"$out" 2>"$err" || rc=$?
  dur=$(( $(date +%s) - start ))

  local status="ok"
  [ "$rc" -ne 0 ] && status="error"
  [ "$rc" -eq 124 ] && status="timeout"

  redact <"$err" >"$errd"
  jq -n --arg status "$status" --argjson exit "$rc" \
        --rawfile stdout "$out" --rawfile stderr "$errd" \
        --argjson dur "$dur" --arg backend "$ctype" --arg model "$model" \
        '{status:$status, exit_code:$exit, backend:$backend, model:$model,
          duration_s:$dur, stdout:$stdout, stderr_sanitized:$stderr}'
  return "$rc"
}

# primary → 실패 시 fallbacks 순차 (set -e 우회: || prc=$?)
prc=0; env_primary="$(run_backend "$rec")" || prc=$?
if [ "$prc" -eq 0 ]; then
  jq -n --argjson e "$env_primary" '$e + {fallback_used:false}'
  exit 0
fi
# primary가 mcp/native라 건너뛴 경우(3), 실제로 무엇이 실행됐는지 envelope에 남긴다 —
# "설정과 다른 백엔드가 조용히 돌았다"를 호출자가 알 수 있어야 한다.
prim_note='{}'
[ "$prc" -eq 3 ] && prim_note="$(jq -n --arg t "$(jq -r '.call_type' <<<"$rec")" '{skipped_primary:$t}')"

nf="$(jq '.fallbacks | length' <<<"$rec")"
env_fb=""; i=0
while [ "$i" -lt "${nf:-0}" ]; do
  fb="$(jq -c --argjson i "$i" '.fallbacks[$i]' <<<"$rec")"
  frc=0; env_fb="$(run_backend "$fb")" || frc=$?
  if [ "$frc" -eq 0 ]; then
    jq -n --argjson e "$env_fb" --argjson n "$prim_note" '$e + {fallback_used:true} + $n'
    exit 0
  fi
  i=$((i+1))
done
# 전부 실패 — 어떤 경로로 와도 유효 envelope를 낸다(빈 문자열이면 jq가 크래시하던 자리).
final="${env_fb:-$env_primary}"
[ -n "$final" ] || final="$(err_envelope 1 "none" "?" "백엔드를 실행하지 못했고 envelope도 없음")"
fb_used=false; [ -n "$env_fb" ] && fb_used=true
jq -n --argjson e "$final" --argjson fb "$fb_used" --argjson n "$prim_note" \
   '$e + {fallback_used:$fb} + $n'
exit 1
