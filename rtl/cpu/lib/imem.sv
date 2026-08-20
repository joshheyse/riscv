`timescale 1ns / 1ps

// Instruction memory.
//
// The core presents fetch requests through `ibus.req` using byte addresses
// (`pc_t`), while the ROM is word-indexed by 32-bit instruction. Address bits
// [1:0] are ignored for this word-only memory; high bits above the configured
// depth intentionally alias for now.
//
//   ibus.req.addr byte range   ROM index
//   ------------------------   --------------------------------
//   0x0000_0000 + 4*N          ibus.req.addr[IndexBits+1:2] = N
//
// Reads are synchronous. A valid request is accepted on one rising edge, then
// `ibus.rsp.valid` and `ibus.rsp.read_data` are updated on that edge for the
// core to observe in the following cycle. `ibus.rsp.read_data` is meaningful
// only when `ibus.rsp.valid` is high.
//
// `InitFile`, when non-empty, is a `$readmemh` file with one 32-bit instruction
// word per line.
//
module imem
  import riscv_pkg::*;
#(
  parameter int unsigned DepthWords = 512,
  parameter              InitFile   = ""
) (
  input logic        clk,
  input logic        rst,
  /* verilator lint_off UNUSEDSIGNAL */
        mem_if.slave ibus
  /* verilator lint_on UNUSEDSIGNAL */
);


  // This slave can always take a request on the cycle it is presented, so
  // acceptance is unconditional. Drive it for real only if that changes.
  assign ibus.req_ready = 1'b1;

  localparam int unsigned IndexBits = $clog2(DepthWords);
  instr_u _rom[DepthWords-1:0];

  initial begin
    if (InitFile != "") begin
      $readmemh(InitFile, _rom);
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      ibus.rsp <= '0;
    end else begin
      if (ibus.req.valid) begin
        ibus.rsp.read_data <= _rom[ibus.req.addr[IndexBits+1:2]];
        ibus.rsp.valid <= 1'b1;
      end else begin
        ibus.rsp.valid <= 1'b0;
      end
    end
  end

endmodule
