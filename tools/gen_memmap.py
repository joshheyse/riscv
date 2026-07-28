#!/usr/bin/env python3
import argparse
from pathlib import Path


def parse_memmap(path):
    data = {}
    constants = {}
    in_constants = False

    for raw_line in path.read_text().splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line.strip():
            continue

        if line == "constants:":
            in_constants = True
            continue

        if in_constants:
            if not line.startswith("  "):
                in_constants = False
            else:
                key, value = line.strip().split(":", 1)
                constants[key.strip()] = int(value.strip(), 0)
                continue

        key, value = line.split(":", 1)
        data[key.strip()] = value.strip()

    data["constants"] = constants
    return data


def c_name(prefix, key):
    return f"{prefix}_{key.upper()}"


def sv_name(key):
    return "".join(part.capitalize() for part in key.split("_"))


def c_value(value):
    return f"0x{value:08x}u"


def sv_value(value):
    return f"32'h{value:08x}"


def write_c_header(memmap, output):
    guard = f"{memmap['board'].upper()}_MEMMAP_H"
    prefix = memmap["c_prefix"]
    constants = memmap["constants"]

    lines = [
        "/* Generated from boards/{}/memmap.yml. Do not edit. */".format(memmap["board"]),
        f"#ifndef {guard}",
        f"#define {guard}",
        "",
    ]

    for key, value in constants.items():
        lines.append(f"#define {c_name(prefix, key):<24} {c_value(value)}")

    if "sim_halt_addr" in constants:
        lines += [
            "",
            "#ifndef RISCV_SOC_SIM_HALT_ADDR",
            f"#define RISCV_SOC_SIM_HALT_ADDR {c_name(prefix, 'sim_halt_addr')}",
            "#endif",
        ]

    lines += ["", "#endif", ""]
    output.write_text("\n".join(lines))


def write_sv_package(memmap, output):
    package = memmap["sv_package"]
    constants = memmap["constants"]

    lines = [
        "// Generated from boards/{}/memmap.yml. Do not edit.".format(memmap["board"]),
        "`timescale 1ns / 1ps",
        "",
        f"package {package};",
    ]

    for key, value in constants.items():
        lines.append(f"  localparam logic [31:0] {sv_name(key):<16} = {sv_value(value)};")

    lines += ["endpackage", ""]
    output.write_text("\n".join(lines))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("memmap", type=Path)
    parser.add_argument("--c-header", type=Path, required=True)
    parser.add_argument("--sv-package", type=Path, required=True)
    args = parser.parse_args()

    memmap = parse_memmap(args.memmap)
    args.c_header.parent.mkdir(parents=True, exist_ok=True)
    args.sv_package.parent.mkdir(parents=True, exist_ok=True)
    write_c_header(memmap, args.c_header)
    write_sv_package(memmap, args.sv_package)


if __name__ == "__main__":
    main()
