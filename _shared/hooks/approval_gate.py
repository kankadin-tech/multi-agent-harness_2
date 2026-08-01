#!/usr/bin/env python3
"""승인 게이트 — `workers_approved`·`max_worker_calls`의 기계적 강제.

CLAUDE.md "Approval Gate"는 종전까지 순수 문서 규약이었다(디스패처도 훅도 검사하지 않음).
이 스크립트가 그 규약의 단일 판정 정본이며 두 진입점에서 쓰인다:

  1) `_shared/adapters/call_worker.sh` 진입부 — cli/api 워커. 셸에서 직접 실행해도 막힌다.
  2) PreToolUse 훅(claude flavor) — MCP(codex)·호스트 서브에이전트(claude-main)처럼
     디스패처를 안 거치는 경로.

사용:
    approval_gate.py --role gemini --brief tasks/<task>/workers/gemini/brief.md
    approval_gate.py --hook          # stdin=PreToolUse JSON, stdout=permissionDecision JSON

종료코드(CLI 모드): 0=허용, 9=거부(사유는 stderr), 0=판정대상 아님.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HARNESS_ROOT = Path(__file__).resolve().parents[2]  # _shared/hooks/ → 하네스 루트
# flavor마다 워커 풀이 다르다(codex flavor엔 claude-critic이 있다) — 목록을 굽지 않고
# backends.json에서 읽는다. 읽기 실패 시에만 claude flavor 기본값으로 폴백.
_FALLBACK_ROLES = ("claude-main", "codex-main", "codex-critic", "gemini")


def worker_roles() -> tuple[str, ...]:
    try:
        data = json.loads((HARNESS_ROOT / "_shared" / "backends.json").read_text(encoding="utf-8"))
        roles = tuple((data.get("workers") or {}).keys())
        return roles or _FALLBACK_ROLES
    except (OSError, json.JSONDecodeError, ValueError, AttributeError):
        return _FALLBACK_ROLES


WORKER_ROLES = worker_roles()


# ── task.md 파싱 (pyyaml 비의존 — 시스템 파이썬만으로 동작해야 한다) ──────────────

def _strip_comments(text: str) -> str:
    """주석 전용 줄 제거. 템플릿의 `# - worker: claude-main` 예시가 승인으로 오독되면 안 된다."""
    return "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))


def approved_workers(task_md: str) -> list[str]:
    text = _strip_comments(task_md)
    m = re.search(r"^workers_approved:[ \t]*(.*)$", text, re.M)
    if not m:
        return []
    if m.group(1).strip() in ("[]", "[ ]"):
        return []
    # 값이 블록 리스트면 다음 비들여쓰기 키 전까지가 그 블록이다(planned_workers 혼입 방지).
    rest = text[m.end():]
    block = re.split(r"^\S", rest, maxsplit=1, flags=re.M)[0]
    return [w.strip().strip("\"'") for w in re.findall(r"^\s*-?\s*worker:\s*(\S+)", block, re.M)]


def max_worker_calls(task_md: str) -> int | None:
    m = re.search(r"^\s*max_worker_calls:\s*(\d+)", _strip_comments(task_md), re.M)
    return int(m.group(1)) if m else None


def calls_so_far(task_dir: Path) -> int:
    log = task_dir / "log.md"
    if not log.is_file():
        return 0
    try:
        return len(re.findall(r"\[WORKER_CALL\]", log.read_text(encoding="utf-8")))
    except OSError:
        return 0


# ── 작업 폴더 탐색 ────────────────────────────────────────────────────────────

def task_dir_from_path(p: Path) -> Path | None:
    """.../tasks/<task>/... 경로에서 tasks/<task>를 찾는다."""
    parts = p.resolve().parts
    for i in range(len(parts) - 2, -1, -1):
        if parts[i] == "tasks":
            return Path(*parts[: i + 2])
    return None


def task_dir_from_text(text: str, cwd: Path) -> Path | None:
    """임의 텍스트(도구 입력 직렬화)에서 tasks/<task> 후보를 찾는다."""
    for m in re.finditer(r"(?:^|[\s\"'=(])((?:/|\./)?[^\s\"']*?tasks/[A-Za-z0-9._-]+)(?=/|[\s\"']|$)", text):
        cand = Path(m.group(1))
        cand = cand if cand.is_absolute() else (cwd / cand)
        if (cand / "task.md").is_file():
            return cand.resolve()
    return None


# ── 판정 ─────────────────────────────────────────────────────────────────────

def decide(role: str, task_dir: Path | None) -> tuple[bool, str]:
    """(허용 여부, 사유). 사유는 어떻게 풀어야 하는지까지 알려준다."""
    if task_dir is None:
        return False, (
            f"'{role}' 워커 호출인데 소속 작업 폴더를 찾지 못했습니다. "
            "워커 호출은 tasks/<task>/ 안에서만 허용됩니다 — task.md를 만들고 "
            "workers_approved에 이 워커를 승인해 주세요."
        )
    task_md_path = task_dir / "task.md"
    if not task_md_path.is_file():
        return False, f"{task_md_path} 가 없습니다. 승인 기록 없이는 워커를 호출할 수 없습니다."
    try:
        task_md = task_md_path.read_text(encoding="utf-8")
    except OSError as e:
        return False, f"task.md를 읽지 못했습니다: {e}"

    approved = approved_workers(task_md)
    if role not in approved:
        listed = ", ".join(approved) if approved else "(없음)"
        return False, (
            f"'{role}'는 {task_md_path} 의 workers_approved에 없습니다. 현재 승인: {listed}. "
            "사용자 승인을 받아 workers_approved에 추가한 뒤 다시 호출하세요."
        )

    budget = max_worker_calls(task_md)
    used = calls_so_far(task_dir)
    if budget is not None and used >= budget:
        return False, (
            f"worker 호출 예산 소진: {used}/{budget} (log.md의 [WORKER_CALL] 기준). "
            "사용자 확인 후 task.md의 max_worker_calls를 올리세요."
        )
    return True, f"승인됨 ({role}, 예산 {used}/{budget if budget is not None else '∞'})"


# ── 훅 모드: PreToolUse 페이로드 → 워커 호출 여부 판별 ──────────────────────────

def role_from_tool(tool_name: str, tool_input: dict) -> str | None:
    """이 도구 호출이 워커 호출이면 role, 아니면 None(게이트 대상 아님)."""
    blob = json.dumps(tool_input, ensure_ascii=False)

    if tool_name == "Bash":
        m = re.search(r"call_worker\.sh\s+(\S+)", tool_input.get("command", ""))
        # 디스패처 자신도 게이트를 돌리므로 중복이지만, 실행 전에 막는 편이 낫다.
        return m.group(1) if m and m.group(1) in WORKER_ROLES else None

    if tool_name.startswith("mcp__codex__"):
        # codex-main과 codex-critic이 같은 MCP 도구를 쓴다 — brief 경로·본문으로 구분.
        guess = "codex-critic" if "codex-critic" in blob else "codex-main"
        return guess if guess in WORKER_ROLES else None

    if tool_name in ("Agent", "Task"):
        sub = tool_input.get("subagent_type") or tool_input.get("agent_type") or ""
        return sub if sub in WORKER_ROLES else None

    return None


def hook_mode() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0  # 페이로드를 못 읽으면 판정하지 않는다(도구를 막지 않음)

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input", {}) or {}
    cwd = Path(payload.get("cwd") or ".")

    role = role_from_tool(tool_name, tool_input)
    if role is None:
        return 0  # 워커 호출이 아님 — 조용히 통과

    blob = json.dumps(tool_input, ensure_ascii=False)
    task_dir = task_dir_from_text(blob, cwd)
    allowed, reason = decide(role, task_dir)

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow" if allowed else "deny",
            "permissionDecisionReason": f"[MultiAgent 승인 게이트] {reason}",
        }
    }, ensure_ascii=False))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="MultiAgent 승인 게이트")
    ap.add_argument("--hook", action="store_true", help="PreToolUse 훅 모드(stdin JSON)")
    ap.add_argument("--role", help="워커 role")
    ap.add_argument("--brief", help="brief 파일 경로 (작업 폴더 유도용)")
    args = ap.parse_args()

    if args.hook:
        return hook_mode()
    if not args.role:
        ap.error("--role 또는 --hook 필요")
    if args.role not in WORKER_ROLES:
        return 0  # 알 수 없는 role은 게이트 대상이 아니다(backends.json이 따로 거부)

    task_dir = task_dir_from_path(Path(args.brief)) if args.brief else None
    allowed, reason = decide(args.role, task_dir)
    if allowed:
        return 0
    print(f"승인 게이트 거부: {reason}", file=sys.stderr)
    return 9


if __name__ == "__main__":
    sys.exit(main())
