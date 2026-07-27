`timescale 1ns / 1ps

// Instruction memory.
//
// The core presents byte addresses (`pc_t`), while the ROM is word-indexed by
// 32-bit instruction. Address bits [1:0] are ignored for this word-only memory;
// high bits above the configured depth intentionally alias for now.
//
//   addr byte range       ROM index
//   -------------------   -----------------------
//   0x0000_0000 + 4*N     addr[IndexBits+1:2] = N
//
// `InitFile`, when non-empty, is a `$readmemh` file with one 32-bit instruction
// word per line.
//
module imem
  import riscv_pkg::*;
#(
  parameter int unsigned DepthWords = 512,
  parameter string InitFile = ""
) (
  input  pc_t    addr,
  output instr_t instr
);

  instr_t rom[DepthWords-1:0];
  initial begin
    if (InitFile != "") begin
      $readmemh(InitFile, rom);
    end
  end

  localparam int unsigned IndexBits = $clog2(DepthWords);
  assign instr = rom[addr[IndexBits+1:2]];

  // intentionally ignored for this small aligned ROM
  logic unused_addr_bits;
  assign unused_addr_bits = |{addr[31:IndexBits+2], addr[1:0]};

endmodule
