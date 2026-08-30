#!/usr/bin/env python3
"""Run the privileged/PMP/Zifencei RISCOF tests on the RTL simulator."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
from pathlib import Path

import yaml


ARCH_TEST_VERSION = "3.8.18"
RELEVANT_GROUPS = ("privilege", "Zifencei")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--suite", type=Path)
    return parser.parse_args()


def run(command: list[str], cwd: Path) -> None:
    subprocess.run(command, cwd=cwd, check=True)


def write_sail_config(path: Path, cwd: Path) -> None:
    result = subprocess.run(
        ["sail_riscv_sim", "--rv32", "--print-default-config"],
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
    )
    uncommented = "\n".join(
        line for line in result.stdout.splitlines() if not line.lstrip().startswith("//")
    )
    config = json.loads(uncommented)
    config["base"]["xtval_nonzero"]["software_breakpoint"] = False
    config["memory"]["misaligned"]["exceptions"]["load_store"] = {
        "Some": "AlignmentException"
    }
    config["extensions"]["Zca"]["supported"] = False
    main_memory = next(
        region
        for region in config["memory"]["regions"]
        if region["attributes"]["mem_type"] == "MainMemory"
    )
    main_memory["base"]["value"] = "0x00000000"
    main_memory["size"]["value"] = "0x00100000"
    dtb_region = next(
        region
        for region in config["memory"]["regions"]
        if region["base"]["value"] == config["memory"]["dtb_address"]["value"]
    )
    config["memory"]["dtb_address"]["value"] = "0x00100000"
    dtb_region["base"]["value"] = "0x00100000"
    config["memory"]["regions"].sort(
        key=lambda region: int(region["base"]["value"], 0)
    )
    path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    repo = args.repo.resolve()
    suite_root = (args.suite or (repo / "build/riscv-arch-test")).resolve()
    if not suite_root.exists():
        suite_root.parent.mkdir(parents=True, exist_ok=True)
        run(
            [
                "riscof",
                "arch-test",
                "--clone",
                "--get-version",
                ARCH_TEST_VERSION,
                "--dir",
                str(suite_root),
            ],
            repo,
        )

    suite = suite_root / "riscv-test-suite"
    env = suite / "env"
    sail_plugin = repo / "tools/riscof/sail_cSim"
    dut_plugin = repo / "tools/riscof/riscv_soc"
    work = repo / "build/riscof_work"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)

    config = repo / "build/riscof_config.ini"
    sail_config = repo / "build/sail_rv32_riscv_soc.json"
    write_sail_config(sail_config, repo)
    config.write_text(
        "\n".join(
            (
                "[RISCOF]",
                "ReferencePlugin=sail_cSim",
                f"ReferencePluginPath={sail_plugin}",
                "DUTPlugin=riscv_soc",
                f"DUTPluginPath={dut_plugin}",
                "",
                "[riscv_soc]",
                f"pluginpath={dut_plugin}",
                f"repo={repo}",
                f"ispec={dut_plugin / 'riscv_soc_isa.yaml'}",
                f"pspec={dut_plugin / 'riscv_soc_platform.yaml'}",
                "jobs=1",
                "",
                "[sail_cSim]",
                f"pluginpath={sail_plugin}",
                f"sailconfig={sail_config}",
                "jobs=1",
                "",
            )
        ),
        encoding="utf-8",
    )

    run(
        [
            "riscof",
            "testlist",
            "--suite",
            str(suite),
            "--env",
            str(env),
            "--config",
            str(config),
            "--work-dir",
            str(work),
        ],
        repo,
    )

    test_list_path = work / "test_list.yaml"
    test_list = yaml.safe_load(test_list_path.read_text(encoding="utf-8"))
    selected = {
        name: entry
        for name, entry in test_list.items()
        if any(f"/{group}/" in entry["test_path"] for group in RELEVANT_GROUPS)
    }
    selected_path = work / "privileged_test_list.yaml"
    selected_path.write_text(yaml.safe_dump(selected), encoding="utf-8")
    print(f"Selected {len(selected)} privileged/Zifencei architectural tests")

    run(
        [
            "riscof",
            "run",
            "--suite",
            str(suite),
            "--env",
            str(env),
            "--config",
            str(config),
            "--work-dir",
            str(work),
            "--testfile",
            str(selected_path),
            "--no-clean",
            "--no-browser",
        ],
        repo,
    )

    report = work / "report.html"
    report_text = report.read_text(encoding="utf-8")
    passed = len(re.findall(r'<td class="col-result">Passed</td>', report_text))
    failed = len(re.findall(r'<td class="col-result">Failed</td>', report_text))
    print(f"Architectural test result: {passed} passed, {failed} failed")
    if passed + failed != len(selected):
        print(
            f"error: report contains {passed + failed} results for "
            f"{len(selected)} selected tests"
        )
        return 1
    if failed:
        print(f"See {report} for failure details")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
