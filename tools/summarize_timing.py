#!/usr/bin/env python3
"""Print a compact summary of a nextpnr JSON timing report."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def numeric(value: Any) -> float | None:
    return float(value) if isinstance(value, (int, float)) else None


def port_name(value: Any) -> str:
    if not isinstance(value, dict):
        return "?"
    cell = value.get("cell", "?")
    port = value.get("port")
    return f"{cell}.{port}" if port else str(cell)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--paths", type=int, default=5, help="number of critical paths to print")
    args = parser.parse_args()

    report = json.loads(args.report.read_text())
    print(f"Timing report: {args.report}")
    for clock, values in report.get("fmax", {}).items():
        achieved = numeric(values.get("achieved"))
        constraint = numeric(values.get("constraint"))
        if achieved is not None and constraint is not None:
            status = "PASS" if achieved >= constraint else "FAIL"
            print(f"  {clock}: {achieved:.2f} MHz ({status} at {constraint:.2f} MHz)")

    paths = []
    for values in report.get("critical_paths", []):
        path = values.get("path", [])
        if not path:
            continue
        delay = sum(numeric(entry.get("delay")) or 0 for entry in path)
        paths.append((delay, values, path))
    paths.sort(key=lambda item: item[0], reverse=True)
    if paths:
        print(f"  Critical path classes ({min(args.paths, len(paths))} shown):")
        for index, (delay, values, path) in enumerate(paths[: args.paths], start=1):
            logic = sum(
                numeric(entry.get("delay")) or 0
                for entry in path
                if entry.get("type") != "routing"
            )
            routing = delay - logic
            print(f"    {index}. {delay:.2f} ns ({logic:.2f} logic, {routing:.2f} routing)")
            print(f"       {values.get('from', '?')} -> {values.get('to', '?')}")
            print(f"       {port_name(path[0].get('from'))} -> {port_name(path[-1].get('to'))}")
    else:
        print("  No detailed paths found in report")


if __name__ == "__main__":
    raise SystemExit(main())
