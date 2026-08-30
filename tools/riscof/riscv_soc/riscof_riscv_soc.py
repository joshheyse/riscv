import logging
import os
import shutil
import struct
import subprocess
from pathlib import Path

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate


logger = logging.getLogger()


class riscv_soc(pluginTemplate):
    __model__ = "riscv-soc"
    __version__ = "1"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get("config")
        if config is None:
            raise RuntimeError("missing riscv_soc RISCOF configuration")

        self.pluginpath = Path(config["pluginpath"]).resolve()
        self.repo = Path(config["repo"]).resolve()
        self.isa_spec = str(Path(config["ispec"]).resolve())
        self.platform_spec = str(Path(config["pspec"]).resolve())
        self.sim_mem = self.repo / "build/boards/sim/cache-4-way/arch-test/program.mem"
        self.sim_bin = self.repo / "build/boards/sim/cache-4-way/arch-test/Vtop_sim"

    def initialise(self, suite, work_dir, archtest_env):
        self.work_dir = Path(work_dir)
        self.archtest_env = Path(archtest_env)

    def build(self, isa_yaml, platform_yaml):
        del isa_yaml, platform_yaml
        self.sim_mem.parent.mkdir(parents=True, exist_ok=True)
        self.sim_mem.write_text("00000013\n", encoding="ascii")
        subprocess.run(
            [
                "make",
                "arch-test-sim",
                "BOARD=sim",
                "BOARD_SIM=top_sim",
                f"ARCH_TEST_MEM={self.sim_mem}",
            ],
            cwd=self.repo,
            check=True,
        )

    @staticmethod
    def _write_mem(binary: Path, destination: Path):
        data = binary.read_bytes()
        data += bytes((-len(data)) % 4)
        with destination.open("w", encoding="ascii") as output:
            for offset in range(0, len(data), 4):
                output.write(f"{struct.unpack_from('<I', data, offset)[0]:08x}\n")

    @staticmethod
    def _symbol(elf: Path, name: str) -> int:
        result = subprocess.run(
            ["riscv64-none-elf-nm", "-n", str(elf)],
            check=True,
            text=True,
            capture_output=True,
        )
        for line in result.stdout.splitlines():
            fields = line.split()
            if len(fields) >= 3 and fields[2] == name:
                return int(fields[0], 16)
        raise RuntimeError(f"{elf}: missing symbol {name}")

    def runTests(self, testList):
        for test_name, test_entry in testList.items():
            test_dir = Path(test_entry["work_dir"])
            test_dir.mkdir(parents=True, exist_ok=True)
            elf = test_dir / "dut.elf"
            binary = test_dir / "dut.bin"
            signature = test_dir / f"{self.name[:-1]}.signature"
            log = test_dir / f"{self.name[:-1]}.log"

            compile_command = [
                "riscv64-none-elf-gcc",
                f"-march={test_entry['isa'].lower()}",
                "-mabi=ilp32",
                "-static",
                "-mcmodel=medany",
                "-fvisibility=hidden",
                "-nostdlib",
                "-nostartfiles",
                "-mno-relax",
                "-Wl,--no-relax",
                "-g",
                "-T",
                str(self.pluginpath / "env/link.ld"),
                "-I",
                str(self.pluginpath / "env"),
                "-I",
                str(self.archtest_env),
                str(test_entry["test_path"]),
                "-o",
                str(elf),
            ]
            compile_command.extend(f"-D{macro}" for macro in test_entry["macros"])
            subprocess.run(compile_command, cwd=test_dir, check=True)
            subprocess.run(
                ["riscv64-none-elf-objcopy", "-O", "binary", str(elf), str(binary)],
                cwd=test_dir,
                check=True,
            )

            self._write_mem(binary, self.sim_mem)
            begin_signature = self._symbol(elf, "begin_signature")
            end_signature = self._symbol(elf, "end_signature")
            command = [
                str(self.sim_bin),
                f"+signature={signature}",
                f"+begin_signature={begin_signature:x}",
                f"+end_signature={end_signature:x}",
            ]
            logger.info("Running %s on riscv-soc", test_name)
            with log.open("w", encoding="utf-8") as output:
                subprocess.run(
                    command,
                    cwd=test_dir,
                    stdout=output,
                    stderr=subprocess.STDOUT,
                    check=True,
                    timeout=120,
                )
