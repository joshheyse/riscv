#!/usr/bin/env python3
"""Lightweight project-specific SystemVerilog style checks."""

from __future__ import annotations

import re
import sys
from pathlib import Path


DECL_TYPES = (
    "logic",
    "wire",
    "word_t",
    "dword_t",
    "byte_t",
    "half_t",
    "pc_t",
    "instr_t",
    "instr_u",
    "regaddr_t",
    "funct3_t",
    "funct7_t",
    "opcode_t",
    "imm_src_t",
    "alu_src_t",
    "alu_result_src_t",
    "alu_select_t",
    "result_src_t",
    "pc_src_t",
    "branch_flags_t",
    "mem_size_t",
    "dbus_if",
    "int",
    "integer",
    "tri1",
    "genvar",
)
DECL_TYPE_RE = rf"(?:{'|'.join(DECL_TYPES)}|[A-Za-z_][A-Za-z0-9_]*_t)"

INSTANCE_TYPES = (
    "alu",
    "alu_decoder",
    "branch_logic",
    "comparator",
    "controller",
    "core",
    "datapath",
    "dmem",
    "extend",
    "gpio_mmio",
    "i2c_mmio",
    "ifu",
    "imem",
    "led_mmio",
    "lsu",
    "main_decoder",
    "onehot_mux",
    "push_button_mmio",
    "reg_file",
    "serial_tick_generator",
    "soc",
    "spi_mmio",
    "timer_mmio",
    "uart_mmio",
    "board_bus",
)

DECL_RE = re.compile(
    rf"^\s*(?:/\*[^*]*\*/\s*)?(?P<type>{DECL_TYPE_RE})\b"
    r"(?:\s+(?:signed|unsigned))*"
    r"(?P<rest>.*?);"
)
INSTANCE_RE = re.compile(
    rf"^\s*(?P<type>{'|'.join(INSTANCE_TYPES)})\b(?:\s*#\s*\()?(?P<rest>.*)"
)
PARAM_INSTANCE_START_RE = re.compile(rf"^\s*(?P<type>{'|'.join(INSTANCE_TYPES)})\b\s*#\s*\(")
PARAM_INSTANCE_NAME_RE = re.compile(r"^\s*\)\s*(?P<name>[A-Za-z_][A-Za-z0-9_$]*)\s*\(")
MODULE_RE = re.compile(r"^\s*module\s+\w+\b(?P<rest>.*)")
INTERFACE_RE = re.compile(r"^\s*interface\s+\w+\b")
ENDMODULE_RE = re.compile(r"^\s*endmodule\b")
ENDINTERFACE_RE = re.compile(r"^\s*endinterface\b")
HEADER_END_RE = re.compile(r"^\s*\)\s*;")
SUBROUTINE_RE = re.compile(r"^\s*(task|function)\b")
ENDSUBROUTINE_RE = re.compile(r"^\s*end(task|function)\b")
PADDED_NAMED_PORT_RE = re.compile(r"\.[A-Za-z_][A-Za-z0-9_$]*\s+\(")


def strip_comment(line: str) -> str:
    return line.split("//", 1)[0]


def names_from_decl(rest: str) -> list[str]:
    rest = re.sub(r"\[[^\]]+\]", " ", rest)
    rest = re.sub(r"=.*?(?=,|$)", " ", rest)
    names = []
    for part in rest.split(","):
        part = part.strip()
        if not part:
            continue
        match = re.match(r"(?P<name>[A-Za-z_][A-Za-z0-9_$]*)", part)
        if match:
            names.append(match.group("name"))
    return names


def instance_name(rest: str) -> str | None:
    if "(" in rest and not rest.lstrip().startswith("#"):
        prefix = rest.split("(", 1)[0].strip()
    else:
        return None
    match = re.search(r"([A-Za-z_][A-Za-z0-9_$]*)\s*$", prefix)
    return match.group(1) if match else None


def check_file(path: Path) -> list[str]:
    errors: list[str] = []
    in_module = False
    in_interface = False
    in_header = False
    in_subroutine = False
    pending_instance_type: str | None = None

    for lineno, raw in enumerate(path.read_text().splitlines(), start=1):
        line = strip_comment(raw)

        if INTERFACE_RE.search(line):
            in_interface = True
            continue
        if ENDINTERFACE_RE.search(line):
            in_interface = False
            continue

        module = MODULE_RE.search(line)
        if module:
            in_module = True
            rest = module.group("rest")
            in_header = ";" not in rest
            continue
        if ENDMODULE_RE.search(line):
            in_module = False
            in_header = False
            continue
        if in_header and HEADER_END_RE.search(line):
            in_header = False
            continue

        if in_module and SUBROUTINE_RE.search(line):
            in_subroutine = True
            continue
        if in_subroutine and ENDSUBROUTINE_RE.search(line):
            in_subroutine = False
            continue

        if not in_module or in_header or in_interface or in_subroutine:
            continue

        if PADDED_NAMED_PORT_RE.search(line):
            errors.append(f"{path}:{lineno}: named port connection should use `.port(expr)`")

        if not raw.startswith("  ") or raw.startswith("    "):
            continue

        if pending_instance_type is not None:
            param_inst = PARAM_INSTANCE_NAME_RE.match(line)
            if param_inst:
                name = param_inst.group("name")
                if not name.startswith("_"):
                    errors.append(f"{path}:{lineno}: instance `{name}` should start with `_`")
                pending_instance_type = None
            continue

        decl = DECL_RE.match(line)
        if decl:
            for name in names_from_decl(decl.group("rest")):
                if name in {"signed", "unsigned"}:
                    continue
                if not name.startswith("_"):
                    errors.append(f"{path}:{lineno}: internal declaration `{name}` should start with `_`")
            continue

        if PARAM_INSTANCE_START_RE.match(line):
            pending_instance_type = PARAM_INSTANCE_START_RE.match(line).group("type")
            continue

        inst = INSTANCE_RE.match(line)
        if inst:
            name = instance_name(inst.group("rest"))
            if name and not name.startswith("_"):
                errors.append(f"{path}:{lineno}: instance `{name}` should start with `_`")

    return errors


def main(argv: list[str]) -> int:
    paths = [Path(arg) for arg in argv[1:]]
    errors: list[str] = []
    for path in paths:
        if path.suffix in {".sv", ".v"} and path.exists():
            errors.extend(check_file(path))

    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
