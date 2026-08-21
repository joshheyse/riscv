#!/usr/bin/env python3
"""Fail unless a synthesized Yosys JSON netlist contains enough ECP5 BRAMs."""

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("netlist", type=Path)
    parser.add_argument("--minimum", type=int, required=True)
    args = parser.parse_args()

    with args.netlist.open(encoding="utf-8") as netlist_file:
        netlist = json.load(netlist_file)

    count = sum(
        cell.get("type") == "DP16KD"
        for module in netlist.get("modules", {}).values()
        for cell in module.get("cells", {}).values()
    )
    if count < args.minimum:
        raise SystemExit(
            f"BRAM check failed: expected at least {args.minimum} DP16KD cells, found {count}"
        )
    print(f"BRAM check: PASS ({count} DP16KD cells, minimum {args.minimum})")


if __name__ == "__main__":
    main()
