module mem_decoder
  import riscv_pkg::*;
(
  input  instr_u    instr,
  output mem_size_t mem_size,
  output logic      mem_unsigned,
  output logic      mem_op_illegal
);

  always_comb begin
    mem_size       = MEM_SIZE_WORD;
    mem_unsigned   = 1'b0;
    mem_op_illegal = 1'b0;

    case (instr.r.opcode)
      OP_LOAD: begin
        case (instr.r.funct3.mem)
          MEM_BYTE: begin
            mem_size     = MEM_SIZE_BYTE;
            mem_unsigned = 1'b0;
          end

          MEM_HALF: begin
            mem_size     = MEM_SIZE_HALF;
            mem_unsigned = 1'b0;
          end

          MEM_WORD: begin
            mem_size     = MEM_SIZE_WORD;
            mem_unsigned = 1'b0;
          end

          MEM_BYTEU: begin
            mem_size     = MEM_SIZE_BYTE;
            mem_unsigned = 1'b1;
          end

          MEM_HALFU: begin
            mem_size     = MEM_SIZE_HALF;
            mem_unsigned = 1'b1;
          end

          default: begin
            mem_op_illegal = 1'b1;
          end
        endcase
      end

      OP_STORE: begin
        case (instr.r.funct3.mem)
          MEM_BYTE: begin
            mem_size = MEM_SIZE_BYTE;
          end

          MEM_HALF: begin
            mem_size = MEM_SIZE_HALF;
          end

          MEM_WORD: begin
            mem_size = MEM_SIZE_WORD;
          end

          default: begin
            mem_op_illegal = 1'b1;
          end
        endcase
      end

      default: begin
      end
    endcase
  end
endmodule
