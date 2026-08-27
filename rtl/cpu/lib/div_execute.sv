`timescale 1ns / 1ps

// RV32M integer divider/remainder executor.
//
// Signed division truncates its quotient toward zero. Its remainder has the
// sign of the dividend (`src_a`) when nonzero. DIVU and REMU interpret both
// operands as unsigned. None of the architecturally defined corner cases trap.
//
//   div_op                    operands  rsp.result
//   ------------------------  --------  ------------------
//   DIV_OP_QUOTIENT_SIGNED    signed    src_a / src_b
//   DIV_OP_QUOTIENT_UNSIGNED  unsigned  src_a / src_b
//   DIV_OP_REMAINDER_SIGNED   signed    src_a % src_b
//   DIV_OP_REMAINDER_UNSIGNED unsigned  src_a % src_b
//
//   corner case                         quotient             remainder
//   ----------------------------------  -------------------  ----------------
//   src_b == 0                          32'hffff_ffff         src_a
//   signed 32'h8000_0000 / 32'hffff_ffff 32'h8000_0000       32'h0000_0000
//
module div_execute
  import riscv_pkg::*;
(
  input logic     clk,
  input logic     rst,
  input logic     cancel,
  input div_req_t req,
  input logic     rsp_ready,

  output logic     req_ready,
  output div_rsp_t rsp
);

  localparam integer_data_t MinSigned = 32'h8000_0000;
  localparam integer_data_t NegOne = 32'hffff_ffff;

  typedef enum logic {
    IDLE,
    DIVIDE
  } state_t;

  state_t               _state;
  logic                 _result_valid;
  integer_data_t        _result;
  integer_data_t        _divisor;
  integer_data_t        _quotient;
  integer_data_t        _remainder;
  logic          [ 5:0] _iteration;
  logic                 _result_negative;
  logic                 _return_remainder;

  logic          [32:0] _shifted_remainder;
  integer_data_t        _next_remainder;
  integer_data_t        _next_quotient;
  integer_data_t        _unsigned_result;
  integer_data_t        _signed_result;

  always_comb begin
    rsp.valid = _result_valid;
    rsp.result = _result;
    req_ready = (_state == IDLE) && !_result_valid;

    _shifted_remainder = {_remainder, _quotient[31]};
    _next_remainder = _shifted_remainder[31:0];
    _next_quotient = {_quotient[30:0], 1'b0};
    if (_shifted_remainder >= {1'b0, _divisor}) begin
      _next_remainder   = integer_data_t'(_shifted_remainder - {1'b0, _divisor});
      _next_quotient[0] = 1'b1;
    end

    _unsigned_result = _return_remainder ? _next_remainder : _next_quotient;
    _signed_result = _result_negative ? (~_unsigned_result + integer_data_t'(1)) : _unsigned_result;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _state <= IDLE;
      _result_valid <= 1'b0;
      _result <= '0;
      _divisor <= '0;
      _quotient <= '0;
      _remainder <= '0;
      _iteration <= '0;
      _result_negative <= 1'b0;
      _return_remainder <= 1'b0;
    end else if (cancel) begin
      _state        <= IDLE;
      _result_valid <= 1'b0;
    end else begin
      if (_result_valid && rsp_ready) begin
        _result_valid <= 1'b0;
      end

      unique case (_state)
        IDLE: begin
          if (req.valid && req_ready) begin
            if (req.src_b == '0) begin
              unique case (req.op)
                DIV_OP_QUOTIENT_SIGNED, DIV_OP_QUOTIENT_UNSIGNED: begin
                  _result <= '1;
                end
                DIV_OP_REMAINDER_SIGNED, DIV_OP_REMAINDER_UNSIGNED: begin
                  _result <= req.src_a;
                end
              endcase
              _result_valid <= 1'b1;
            end else if (req.src_a == MinSigned && req.src_b == NegOne &&
                      (req.op == DIV_OP_QUOTIENT_SIGNED || req.op == DIV_OP_REMAINDER_SIGNED)) begin
              _result       <= req.op == DIV_OP_QUOTIENT_SIGNED ? MinSigned : '0;
              _result_valid <= 1'b1;
            end else begin
              _return_remainder <= (req.op == DIV_OP_REMAINDER_SIGNED) ||
                                   (req.op == DIV_OP_REMAINDER_UNSIGNED);
              if ((req.op == DIV_OP_QUOTIENT_SIGNED) || (req.op == DIV_OP_REMAINDER_SIGNED)) begin
                _divisor <= req.src_b[31] ? (~req.src_b + integer_data_t'(1)) : req.src_b;
                _quotient <= req.src_a[31] ? (~req.src_a + integer_data_t'(1)) : req.src_a;
                _result_negative <= (req.op == DIV_OP_REMAINDER_SIGNED) ? req.src_a[31] :
                                    (req.src_a[31] ^ req.src_b[31]);
              end else begin
                _divisor <= req.src_b;
                _quotient <= req.src_a;
                _result_negative <= 1'b0;
              end
              _remainder <= '0;
              _iteration <= '0;
              _state <= DIVIDE;
            end
          end
        end
        DIVIDE: begin
          _remainder <= _next_remainder;
          _quotient  <= _next_quotient;
          if (_iteration == 6'd31) begin
            _result       <= _signed_result;
            _result_valid <= 1'b1;
            _state        <= IDLE;
          end else begin
            _iteration <= _iteration + 6'd1;
          end
        end
      endcase
    end
  end

endmodule
