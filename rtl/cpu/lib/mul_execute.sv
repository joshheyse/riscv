`timescale 1ns / 1ps

// Iterative RV32M integer multiplier.
//
// One multiplier bit is consumed per cycle using shift-and-add multiplication.
// Signed high-word operations first convert signed operands to magnitudes, then
// apply the product sign after all 32 iterations. MUL uses unsigned bit patterns
// because its low 32 bits are identical for signed and unsigned multiplication.
//
//   mul_op          src_a       src_b       rsp.result
//   --------------  ----------  ----------  -----------------------
//   MUL_OP_LOW      either      either      product[31:0]
//   MUL_OP_HIGH_SS  signed      signed      product[63:32]
//   MUL_OP_HIGH_SU  signed      unsigned    product[63:32]
//   MUL_OP_HIGH_UU  unsigned    unsigned    product[63:32]
//
module mul_execute
  import riscv_pkg::*;
(
  input logic     clk,
  input logic     rst,
  input logic     cancel,
  input mul_req_t req,
  input logic     rsp_ready,

  output logic     req_ready,
  output mul_rsp_t rsp
);

  typedef enum logic [1:0] {
    IDLE,
    MULTIPLY,
    RESPOND
  } state_t;

  state_t          _state;
  logic      [63:0] _accumulator;
  logic      [63:0] _multiplicand;
  integer_data_t   _multiplier;
  logic      [ 5:0] _iteration;
  logic             _product_negative;
  logic             _return_high;
  integer_data_t    _result;

  logic      [63:0] _next_accumulator;
  logic      [63:0] _unsigned_product;
  logic      [63:0] _signed_product;

  always_comb begin
    req_ready = (_state == IDLE);
    rsp = '{valid: (_state == RESPOND), result: _result};

    _next_accumulator = _accumulator;
    if (_multiplier[0]) begin
      _next_accumulator = _accumulator + _multiplicand;
    end
    _unsigned_product = _next_accumulator;
    _signed_product = _product_negative ? (~_unsigned_product + 64'd1) : _unsigned_product;
  end

  always_ff @(posedge clk) begin
    if (rst || cancel) begin
      _state <= IDLE;
      _accumulator <= '0;
      _multiplicand <= '0;
      _multiplier <= '0;
      _iteration <= '0;
      _product_negative <= 1'b0;
      _return_high <= 1'b0;
      _result <= '0;
    end else begin
      unique case (_state)
        IDLE: begin
          if (req.valid && req_ready) begin
            logic signed_a;
            logic signed_b;

            signed_a = (req.op == MUL_OP_HIGH_SS) || (req.op == MUL_OP_HIGH_SU);
            signed_b = (req.op == MUL_OP_HIGH_SS);
            _multiplicand <= {
                32'b0,
                (signed_a && req.src_a[31]) ? (~req.src_a + integer_data_t'(1)) : req.src_a
            };
            _multiplier <=
                (signed_b && req.src_b[31]) ? (~req.src_b + integer_data_t'(1)) : req.src_b;
            _product_negative <= (signed_a && req.src_a[31]) ^ (signed_b && req.src_b[31]);
            _return_high <= (req.op != MUL_OP_LOW);
            _accumulator <= '0;
            _iteration <= '0;
            _state <= MULTIPLY;
          end
        end

        MULTIPLY: begin
          _accumulator <= _next_accumulator;
          _multiplicand <= _multiplicand << 1;
          _multiplier <= _multiplier >> 1;
          if (_iteration == 6'd31) begin
            _result <= _return_high ? _signed_product[63:32] : _signed_product[31:0];
            _state <= RESPOND;
          end else begin
            _iteration <= _iteration + 6'd1;
          end
        end

        RESPOND: begin
          if (rsp.valid && rsp_ready) begin
            _result <= '0;
            _state <= IDLE;
          end
        end
      endcase
    end
  end

endmodule
