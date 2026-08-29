#!/usr/bin/env python3
"""Run the fixed Sv32 workload with the TLB disabled and enabled."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


HALT_RE = re.compile(r"top_sim: halt code 0x([0-9a-fA-F]+)")
STATS_RE = re.compile(r"top_sim: stats cycles=(\d+) instret=(\d+)")


@dataclass(frozen=True)
class Result:
    measured_cycles: int
    total_cycles: int
    instret: int


def run_configuration(root: Path, design: str, cache_ways: int, enabled: bool) -> Result:
    command = [
        "make",
        "--no-print-directory",
        "board-sim",
        f"DESIGN={design}",
        "BOARD=sim",
        "BOARD_SIM=top_sim",
        "APP=examples/apps/sv32_tlb_stress",
        "RISCV_ARCH=rv32i_zicsr",
        "MEM_BYTES=131072",
        f"CACHE_WAYS={cache_ways}",
        f"TLB_ENABLED={int(enabled)}",
    ]
    completed = subprocess.run(command, cwd=root, text=True, capture_output=True, check=False)
    output = completed.stdout + completed.stderr
    if completed.returncode != 0:
        print(output, file=sys.stderr, end="")
        raise RuntimeError(f"TLB {'enabled' if enabled else 'disabled'} run failed")

    halt_match = HALT_RE.search(output)
    stats_match = STATS_RE.search(output)
    if halt_match is None or stats_match is None:
        raise RuntimeError("simulator output did not contain benchmark results")

    measured_cycles = int(halt_match.group(1), 16)
    if measured_cycles == 0xFFFFFFFF:
        raise RuntimeError("benchmark checksum failed")

    return Result(
        measured_cycles=measured_cycles,
        total_cycles=int(stats_match.group(1)),
        instret=int(stats_match.group(2)),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--design", default="pipelined")
    parser.add_argument("--cache-ways", type=int, default=4)
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    disabled = run_configuration(root, args.design, args.cache_ways, enabled=False)
    enabled = run_configuration(root, args.design, args.cache_ways, enabled=True)

    if disabled.instret != enabled.instret:
        raise RuntimeError(
            f"retired instruction counts differ: {disabled.instret} != {enabled.instret}"
        )

    speedup = disabled.measured_cycles / enabled.measured_cycles
    reduction = 100.0 * (disabled.measured_cycles - enabled.measured_cycles) / disabled.measured_cycles

    print("TLB       measured cycles  total cycles  instret")
    print(
        f"disabled  {disabled.measured_cycles:15,d}  {disabled.total_cycles:12,d}  "
        f"{disabled.instret:7,d}"
    )
    print(
        f"enabled   {enabled.measured_cycles:15,d}  {enabled.total_cycles:12,d}  "
        f"{enabled.instret:7,d}"
    )
    print(f"speedup: {speedup:.2f}x")
    print(f"measured-cycle reduction: {reduction:.1f}%")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"tlb-perf: {error}", file=sys.stderr)
        raise SystemExit(1) from error
