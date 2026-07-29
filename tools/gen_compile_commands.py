#!/usr/bin/env python3
import argparse
import json
import shutil
import subprocess
from pathlib import Path


C_FLAGS = [
    "--target=riscv32-unknown-elf",
    "-march=rv32i",
    "-mabi=ilp32",
    "-ffreestanding",
    "-nostdinc",
    "-nostdlib",
    "-nostartfiles",
    "-fno-builtin",
    "-Wall",
    "-Wextra",
    "-Os",
    "-std=c11",
]

CXX_FLAGS = [
    "--target=riscv32-unknown-elf",
    "-march=rv32i",
    "-mabi=ilp32",
    "-ffreestanding",
    "-nostdinc",
    "-nostdlib",
    "-nostartfiles",
    "-fno-builtin",
    "-Wall",
    "-Wextra",
    "-Os",
    "-std=c++20",
    "-fno-exceptions",
    "-fno-rtti",
    "-fno-use-cxa-atexit",
]


def rel(path, root):
    return path.relative_to(root).as_posix()


def add_entry(commands, root, compiler, flags, include_dirs, source, extra_flags=None):
    args = [compiler, *flags]
    for include_dir in include_dirs:
        args.append(f"-I{rel(include_dir, root)}")
    if extra_flags:
        args.extend(extra_flags)
    args.extend(["-c", rel(source, root)])
    commands.append({
        "directory": root.as_posix(),
        "file": rel(source, root),
        "arguments": args,
    })


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--board", default="lfe5um5g_85f_evn")
    parser.add_argument("--output", type=Path, default=Path("compile_commands.json"))
    parser.add_argument("--clang-resource-dir")
    args = parser.parse_args()

    root = args.root.resolve()
    board_dir = root / "boards" / args.board
    include_dirs = [
        root / "sdk" / "riscv32" / "include",
        board_dir / "include",
    ]
    resource_dir = args.clang_resource_dir
    if resource_dir is None and shutil.which("clang"):
        resource_dir = subprocess.check_output(["clang", "-print-resource-dir"], text=True).strip()

    commands = []
    for source in sorted((root / "examples" / "apps").glob("**/*")):
        if source.suffix == ".c":
            add_entry(commands, root, "clang", C_FLAGS, include_dirs, source,
                      ["-isystem", f"{resource_dir}/include"] if resource_dir else None)
        elif source.suffix in {".cc", ".cpp"}:
            add_entry(commands, root, "clang++", CXX_FLAGS, include_dirs, source,
                      ["-isystem", f"{resource_dir}/include"] if resource_dir else None)

    for include_dir in include_dirs:
        for source in sorted(include_dir.glob("**/*.h")):
            extra_flags = ["-x", "c-header"]
            if resource_dir:
                extra_flags += ["-isystem", f"{resource_dir}/include"]
            add_entry(commands, root, "clang", C_FLAGS, include_dirs, source, extra_flags)

    args.output.write_text(json.dumps(commands, indent=2) + "\n")


if __name__ == "__main__":
    main()
