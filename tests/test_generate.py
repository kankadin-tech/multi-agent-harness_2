#!/usr/bin/env python3
"""L1/A2: 각 flavor를 임시폴더에 생성 → validate가 전부 PASS인지.

외부 호출 없음, 결정적. validate 체크 *개수*는 하드코딩하지 않는다
(F4 등으로 체크가 늘어도 안 깨지도록 — "전부 PASS"와 exit 0만 단언).

knot·요금가드 설치는 v3.0.0부터 loadout 담당 — 주입 테스트는 제거했고,
기본 생성물에 그 잔재(관리블록·가드 배선)가 없다는 부재 단언만 남긴다.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
GEN = REPO / "plugins" / "multi-agent-starter" / "skills" / "configure-multiagent" / "generator"
FLAVORS = sorted(p.name for p in (GEN / "templates").iterdir() if p.is_dir())
INSTRUCTION_FILE = {"claude": "CLAUDE.md", "codex": "AGENTS.md", "antigravity": "AGENTS.md"}
KNOT_START, KNOT_END = "<!-- knot:start -->", "<!-- knot:end -->"


def run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True)


def init(tgt: Path, f: str) -> subprocess.CompletedProcess:
    return run([sys.executable, str(GEN / "init.py"),
                "--flavor", f, "--target", str(tgt), "--yes", "--no-validate"])


def _quota_guard_absent(tgt: Path, f: str) -> bool:
    """요금가드(coach) 배선이 생성물에 없는지 — 그 설치는 loadout 소관(D10 v3.0.0 이관).

    claude flavor는 2026-08-01부터 starter가 `.claude/settings.json`을 **직접 깐다**(승인 게이트
    훅 배선, D14). 따라서 "파일 부재"가 아니라 "요금가드 배선 부재"를 단언해야 한다 — 두 배선은
    같은 파일에 살 수 있고, 여기서 막으려는 것은 coach 쪽뿐이다.
    """
    if f == "claude":
        s = tgt / ".claude" / "settings.json"
        return "coach" not in s.read_text(encoding="utf-8") if s.is_file() else True
    if f == "codex":
        return not (tgt / "_shared" / "guard" / "codex_goal_watch.mjs").is_file()
    return True  # antigravity는 가드 배선 산출물 자체가 없음


def validate_all_pass() -> int:
    fails = 0
    for f in FLAVORS:
        with tempfile.TemporaryDirectory() as d:
            tgt = Path(d) / f"sys-{f}"
            if init(tgt, f).returncode != 0:
                print(f"  FAIL [{f}] init exit nonzero"); fails += 1; continue
            v = run([sys.executable, str(GEN / "validate.py"),
                     "--flavor", f, "--target", str(tgt)])
            ok = v.returncode == 0 and "전부 PASS" in v.stdout
            print(f"  {'PASS' if ok else 'FAIL'} [{f}] validate exit {v.returncode}")
            if not ok:
                print(v.stdout); fails += 1
    return fails


def slim_checks() -> int:
    """기본 생성물에 knot 관리블록·가드 배선 잔재가 없는지 (v3 슬림화 회귀 방지)."""
    fails = 0
    for f in FLAVORS:
        with tempfile.TemporaryDirectory() as d:
            tgt = Path(d) / f"plain-{f}"
            init(tgt, f)
            txt = (tgt / INSTRUCTION_FILE[f]).read_text(encoding="utf-8")
            no_knot = KNOT_START not in txt and KNOT_END not in txt
            print(f"  {'PASS' if no_knot else 'FAIL'} [{f}] 기본 init 관리블록 부재")
            fails += not no_knot
            no_guard = _quota_guard_absent(tgt, f)
            print(f"  {'PASS' if no_guard else 'FAIL'} [{f}] 기본 init 요금가드 배선 부재")
            fails += not no_guard
            # 반대로 승인 게이트(D14)는 3 flavor 전부에 깔려야 한다.
            gate = (tgt / "_shared" / "hooks" / "approval_gate.py").is_file()
            print(f"  {'PASS' if gate else 'FAIL'} [{f}] 승인 게이트 판정기 배포")
            fails += not gate
    return fails


def main() -> None:
    fails = validate_all_pass() + slim_checks()
    print(f"test_generate: {'all pass' if not fails else f'{fails} fail'}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
