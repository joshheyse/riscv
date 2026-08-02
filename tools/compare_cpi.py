#!/usr/bin/env python3
"""Compare simulated cycles-per-instruction for board firmware apps."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from run_board_app_tests import APP_TESTS


STATS_RE = re.compile(r"top_sim: stats cycles=(?P<cycles>\d+) instret=(?P<instret>\d+)")
DESIGNS = ("single_stage", "pipelined")


@dataclass(frozen=True)
class RunStats:
    cycles: int
    instret: int

    @property
    def cpi(self) -> float:
        return self.cycles / self.instret


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--board", default="sim")
    parser.add_argument("--sim", default="top_sim")
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument(
        "tests",
        nargs="*",
        choices=[test.name for test in APP_TESTS],
        help="app tests to run; defaults to the full suite",
    )
    return parser.parse_args()


def run_app(repo: Path, design: str, board: str, sim: str, app: str) -> RunStats:
    cmd = [
        "make",
        "board-sim",
        f"DESIGN={design}",
        f"BOARD={board}",
        f"BOARD_SIM={sim}",
        f"APP={app}",
    ]

    result = subprocess.run(
        cmd,
        cwd=repo,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    match = STATS_RE.search(result.stdout)

    if result.returncode != 0 or match is None:
        print(f"{design} {app}: FAIL")
        print(f"  command: {' '.join(cmd)}")
        print(f"  exit: {result.returncode}")
        if match is None:
            print("  missing: top_sim stats line")
        print("  tail:")
        for line in result.stdout.splitlines()[-20:]:
            print(f"    {line}")
        raise RuntimeError(f"{design} failed for {app}")

    cycles = int(match.group("cycles"))
    instret = int(match.group("instret"))
    if instret == 0:
        raise RuntimeError(f"{design} retired zero instructions for {app}")

    return RunStats(cycles=cycles, instret=instret)


def main() -> int:
    args = parse_args()
    selected = {name for name in args.tests}
    tests = [test for test in APP_TESTS if not selected or test.name in selected]

    rows: list[tuple[str, RunStats, RunStats]] = []
    try:
        for test in tests:
            stats = {
                design: run_app(args.repo, design, args.board, args.sim, test.app)
                for design in DESIGNS
            }
            rows.append((test.name, stats["single_stage"], stats["pipelined"]))
    except RuntimeError as exc:
        print(f"board-cpi: {exc}", file=sys.stderr)
        return 1

    print(
        f"{'app':<20} "
        f"{'single cycles':>13} {'single inst':>11} {'single CPI':>10} "
        f"{'pipe cycles':>11} {'pipe inst':>9} {'pipe CPI':>9} "
        f"{'cycle x':>8}"
    )
    for name, single, pipe in rows:
        cycle_speedup = single.cycles / pipe.cycles
        print(
            f"{name:<20} "
            f"{single.cycles:>13} {single.instret:>11} {single.cpi:>10.2f} "
            f"{pipe.cycles:>11} {pipe.instret:>9} {pipe.cpi:>9.2f} "
            f"{cycle_speedup:>8.2f}"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
