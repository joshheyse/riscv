`timescale 1ns / 1ps

module amo_alu
  import riscv_pkg::*;
(
  input amo_op_e op,
  input integer_data_t old_value,
  input integer_data_t operand,
  output integer_data_t new_value
);

  integer_data_t _add;
  integer_data_t _and;
  integer_data_t _or;
  integer_data_t _xor;
  assign _add = old_value + operand;
  assign _and = old_value & operand;
  assign _or  = old_value | operand;
  assign _xor = old_value ^ operand;

  always_comb begin
    new_value = '0;
    case (op)
      AMO_OP_ADD:  new_value = _add;
      AMO_OP_SWAP: new_value = operand;
      AMO_OP_AND:  new_value = _and;
      AMO_OP_OR:   new_value = _or;
      AMO_OP_XOR:  new_value = _xor;
      AMO_OP_MAX:  new_value = ($signed(old_value) > $signed(operand)) ? old_value : operand;
      AMO_OP_MIN:  new_value = ($signed(old_value) < $signed(operand)) ? old_value : operand;
      AMO_OP_MAXU: new_value = (old_value > operand) ? old_value : operand;
      AMO_OP_MINU: new_value = (old_value < operand) ? old_value : operand;
      AMO_OP_LR:   new_value = old_value;
      AMO_OP_SC:   new_value = operand;
      default: begin
      end
    endcase
  end

endmodule
