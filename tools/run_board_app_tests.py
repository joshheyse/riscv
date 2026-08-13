#!/usr/bin/env python3
"""Run simulated-board firmware regressions and check observable output."""

from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class AppTest:
    name: str
    app: str
    expected: tuple[str, ...]
    run_args: tuple[str, ...] = ()


APP_TESTS = (
    AppTest(
        name="uart_halt_c",
        app="examples/apps/uart_halt_c",
        expected=(
            "top_sim: uart byte 0x6f",
            "top_sim: uart byte 0x6b",
            "top_sim: uart byte 0x0a",
            "top_sim: halt code 0x00000000",
        ),
    ),
    AppTest(
        name="uart_pattern_halt",
        app="examples/apps/uart_pattern_halt",
        expected=(
            "top_sim: uart byte 0x30",
            "top_sim: uart byte 0x31",
            "top_sim: uart byte 0x32",
            "top_sim: uart byte 0x33",
            "top_sim: uart byte 0x34",
            "top_sim: uart byte 0x35",
            "top_sim: uart byte 0x36",
            "top_sim: uart byte 0x37",
            "top_sim: uart byte 0x38",
            "top_sim: uart byte 0x39",
            "top_sim: uart byte 0x61",
            "top_sim: uart byte 0x62",
            "top_sim: uart byte 0x63",
            "top_sim: uart byte 0x64",
            "top_sim: uart byte 0x65",
            "top_sim: uart byte 0x66",
            "top_sim: uart byte 0x0a",
            "top_sim: halt code 0x00000000",
        ),
    ),
    AppTest(
        name="memory_copy_halt",
        app="examples/apps/memory_copy_halt",
        expected=(
            "top_sim: uart byte 0x50",
            "top_sim: uart byte 0x0a",
            "_led: 0x5a",
            "top_sim: halt code 0x00000000",
        ),
    ),
    AppTest(
        name="led_count_halt",
        app="examples/apps/led_count_halt",
        expected=("_led: 0xaa", "top_sim: halt code 0x00000000"),
    ),
    AppTest(
        name="plic_uart_irq_halt",
        app="examples/apps/plic_uart_irq_halt",
        expected=(
            "top_sim: checkpoint plic claim id=0x00000001",
            "top_sim: checkpoint plic complete id=0x00000001",
            "top_sim: checkpoint mret retired",
            "top_sim: checkpoint uart tx accepted",
            "top_sim: checkpoint simulation halt code=0x00000000",
            "top_sim: uart byte 0x50",
            "top_sim: uart byte 0x41",
            "top_sim: uart byte 0x53",
            "top_sim: uart byte 0x53",
            "top_sim: uart byte 0x0a",
            "top_sim: halt code 0x00000000",
        ),
        run_args=("+uart_rx=P", "+plic-checkpoints"),
    ),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--design", default="single_stage")
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


def run_test(repo: Path, design: str, board: str, sim: str, test: AppTest) -> bool:
    cmd = [
        "make",
        "board-sim",
        f"DESIGN={design}",
        f"BOARD={board}",
        f"BOARD_SIM={sim}",
        f"APP={test.app}",
        f"RUN_ARGS={'+uart-bytes ' + ' '.join(test.run_args)}",
    ]

    result = subprocess.run(
        cmd,
        cwd=repo,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )

    missing = [expected for expected in test.expected if expected not in result.stdout]
    ok = result.returncode == 0 and not missing

    status = "PASS" if ok else "FAIL"
    print(f"{test.name:<20} {status}")

    if not ok:
        print(f"  command: {' '.join(cmd)}")
        print(f"  exit: {result.returncode}")
        for expected in missing:
            print(f"  missing: {expected}")
        print("  tail:")
        for line in result.stdout.splitlines()[-20:]:
            print(f"    {line}")

    return ok


def main() -> int:
    args = parse_args()
    selected = {name for name in args.tests}
    tests = [test for test in APP_TESTS if not selected or test.name in selected]

    failed = False
    for test in tests:
        failed = not run_test(args.repo, args.design, args.board, args.sim, test) or failed

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
