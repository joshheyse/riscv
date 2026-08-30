import logging
import shutil
import subprocess
from pathlib import Path

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate


logger = logging.getLogger()


class sail_cSim(pluginTemplate):
    __model__ = "sail-c-simulator"
    __version__ = "1"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get("config")
        if config is None:
            raise RuntimeError("missing sail_cSim RISCOF configuration")
        self.pluginpath = Path(config["pluginpath"]).resolve()
        self.sailconfig = Path(config["sailconfig"]).resolve()

    def initialise(self, suite, work_dir, archtest_env):
        del suite
        self.work_dir = Path(work_dir)
        self.archtest_env = Path(archtest_env)

    def build(self, isa_yaml, platform_yaml):
        del isa_yaml, platform_yaml
        for executable in ("riscv64-none-elf-gcc", "sail_riscv_sim"):
            if shutil.which(executable) is None:
                raise RuntimeError(f"missing executable: {executable}")

    def runTests(self, testList):
        for test_name, test_entry in testList.items():
            test_dir = Path(test_entry["work_dir"])
            test_dir.mkdir(parents=True, exist_ok=True)
            elf = test_dir / "ref.elf"
            signature = test_dir / f"{self.name[:-1]}.signature"
            log = test_dir / f"{self.name[:-1]}.log"

            command = [
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
            command.extend(f"-D{macro}" for macro in test_entry["macros"])
            subprocess.run(command, cwd=test_dir, check=True)

            logger.info("Running %s on Sail", test_name)
            with log.open("w", encoding="utf-8") as output:
                subprocess.run(
                    [
                        "sail_riscv_sim",
                        "--config",
                        str(self.sailconfig),
                        f"--test-signature={signature}",
                        str(elf),
                    ],
                    cwd=test_dir,
                    stdout=output,
                    stderr=subprocess.STDOUT,
                    check=True,
                    timeout=120,
                )
