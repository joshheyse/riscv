{
  description = "riscv-soc — RISC-V processor / SoC development (toolflow from 'RISC-V System-on-Chip Design')";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Bare-metal RISC-V cross toolchain (riscv64-none-elf-*).
        # The book uses the riscv64-unknown-elf- prefix; only the name
        # differs, riscof/Makefiles take the prefix as a variable.
        crossPkgs = pkgs.pkgsCross.riscv64-embedded.buildPackages;
        toolchain = [
          crossPkgs.gcc       # riscv64-none-elf-gcc (+ ld/as via wrapper)
          crossPkgs.binutils  # objdump/objcopy/readelf
          crossPkgs.gdb       # riscv64-none-elf-gdb
        ];

        # ISA simulators / golden reference models.
        isaSim = [
          pkgs.spike       # riscv-isa-sim — the standard ISA simulator
          pkgs.sail-riscv  # formal golden model, riscof reference
          pkgs.qemu        # qemu-system-riscv64 — fast full-system emulation
        ];

        # RTL simulation / verification.
        rtlSim = [
          pkgs.verilator  # fast cycle-accurate C++ sim + linter
          pkgs.gtkwave    # waveform viewer
          pkgs.verible    # verible-verilog-{ls,format,lint}
          pkgs.asm-lsp    # assembly language server (RISC-V aware, see .asm-lsp.toml)
        ];

        # FPGA synthesis, place-and-route, bitstream packing, and programming.
        # ECP5 uses yosys + nextpnr-ecp5 + Project Trellis/ecppack.
        # iCE40 uses yosys + nextpnr-ice40 + IceStorm/icepack.
        svElab = pkgs.stdenv.mkDerivation rec {
          pname = "sv-elab";
          version = "unstable-2026-07-14";

          src = pkgs.fetchFromGitHub {
            owner = "povik";
            repo = "sv-elab";
            rev = "3dddccd478618d68f8a5e160fb4b5783c4da35d4";
            fetchSubmodules = true;
            hash = "sha256-ori7RYPvn1Ghnl1hAlPpIqlAU2nPUV628gktUXWegT0=";
          };

          nativeBuildInputs = [
            pkgs.cmake
            pkgs.git
            pkgs.ninja
            pkgs.python3
          ];

          buildInputs = [
            pkgs.boost
            pkgs.tomlplusplus
            pkgs.yosys
          ];

          cmakeFlags = [
            "-DSLANG_USE_SYSTEM_BOOST=ON"
            "-DSLANG_USE_SYSTEM_TOMLPLUSPLUS=ON"
            "-DYOSYS_CONFIG=${pkgs.yosys}/bin/yosys-config"
          ];

          installPhase = ''
            runHook preInstall
            install -Dm755 slang.so $out/share/yosys/plugins/slang.so
            runHook postInstall
          '';
        };

        fpga = [
          pkgs.yosys
          svElab
          pkgs.nextpnr
          pkgs.trellis
          pkgs.icestorm
          pkgs.openfpgaloader
        ];

        # riscof drives the RISC-V architecture compliance tests,
        # comparing your core (DUT) against the Sail golden model.
        # setuptools provides the distutils shim riscof still imports.
        python = pkgs.python3.withPackages (ps: [ ps.riscof ps.setuptools ]);

        misc = [
          pkgs.bash-completion
          pkgs.dtc  # device tree compiler (spike/qemu platform descriptions)
          pkgs.just
          pkgs.llvmPackages_21.clang-unwrapped
          pkgs.clang-tools
          python
        ];
      in
      {
        packages.sv-elab = svElab;

        devShells.default = pkgs.mkShell {
          name = "riscv-soc";
          packages = toolchain ++ isaSim ++ rtlSim ++ fpga ++ misc;

          # Cross-compile prefix, used by the justfile and riscof configs.
          CROSS_COMPILE = "riscv64-none-elf-";
          YOSYS_PLUGIN_PATH = "${svElab}/share/yosys/plugins";

          shellHook = ''
            echo "riscv-soc dev shell"
            echo "  gcc        $(riscv64-none-elf-gcc --version | head -n1)"
            echo "  spike      $(spike --help 2>&1 | head -n1)"
            echo "  sail       $(ls ${pkgs.sail-riscv}/bin | tr '\n' ' ')"
            echo "  qemu       $(qemu-system-riscv64 --version | head -n1)"
            echo "  verilator  $(verilator --version)"
            echo "  yosys      $(yosys -V)"
            echo "  sv-elab    $(yosys -m slang -Q -p 'help read_slang' >/dev/null && echo read_slang)"
            echo "  nextpnr    $(nextpnr-ecp5 --version 2>&1 | head -n1)"
            echo "  loader     $(openFPGALoader --Version 2>&1 | head -n1)"
            echo "  riscof     $(riscof --version 2>/dev/null | head -n1)"
            echo "  clangd     $(clangd --version | head -n1)"
            echo ""
            echo "Recipes: just --list"

            if [ -n "''${BASH_VERSION:-}" ]; then
              source ${pkgs.bash-completion}/share/bash-completion/bash_completion
              source <(just --completions bash)
            elif [ -n "''${ZSH_VERSION:-}" ]; then
              autoload -Uz compinit
              compinit
              source <(just --completions zsh)
            fi
          '';
        };
      });
}
