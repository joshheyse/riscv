
`timescale 1ns / 1ps

module ifu_pipelined
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  input logic clk,
  input logic rst,
  input logic fetch_en,
  input logic redirect_en,
  input pc_t  redirect_pc,

  output pc_t    pc,
  output if_id_t fetched,

  ibus_if.master ibus
);

  logic _request_valid;
  pc_t  _request_pc;
  logic _request_issued;
  logic _drop_rsp;

  assign _request_issued = !rst && fetch_en && !_request_valid && !_drop_rsp;
  assign ibus.req.valid  = _request_issued;
  assign ibus.req.addr   = pc;

  always_ff @(posedge clk) begin
    if (rst) begin
      pc <= '0;
      fetched <= '0;
      _request_valid <= '0;
      _request_pc <= '0;
      _drop_rsp <= 1'b0;
    end else begin
      if (redirect_en) begin
        fetched <= '0;
        pc <= redirect_pc;
        _drop_rsp <= _request_valid && !ibus.rsp.ready;
        _request_valid <= 1'b0;
      end else begin
        if (fetch_en && fetched.valid) begin
          fetched <= '0;
        end

        if (ibus.rsp.ready && _drop_rsp) begin
          _drop_rsp <= 1'b0;
        end

        if (ibus.rsp.ready && _request_valid) begin
          fetched <= '{valid: 1'b1, pc: _request_pc, instr: ibus.rsp.instr};
          _request_valid <= 1'b0;
        end

        if (_request_issued) begin
          _request_valid <= 1'b1;
          _request_pc <= pc;
          pc <= pc + pc_t'(4);
        end
      end

    end

  end

endmodule
