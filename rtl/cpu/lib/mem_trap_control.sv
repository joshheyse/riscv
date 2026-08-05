`timescale 1ns / 1ps

module mem_trap_control
  import riscv_pkg::*;
(

  input  logic      valid,
  input  mem_addr_t addr,
  input  mem_size_t mem_size,
  input  logic      mem_write_en,
  output trap_req_t trap
);

  logic _address_misaligned;

  always_comb begin
    trap = '0;
    _address_misaligned = 1'b0;

    unique case (mem_size)
      MEM_SIZE_BYTE: begin
        _address_misaligned = 1'b0;
      end
      MEM_SIZE_HALF: begin
        if (addr[0] != 1'b0) begin
          _address_misaligned = 1'b1;
        end
      end
      MEM_SIZE_WORD: begin
        if (addr[1:0] != 2'b00) begin
          _address_misaligned = 1'b1;
        end
      end
    endcase

    if (valid && _address_misaligned) begin
      trap.valid = 1'b1;
      trap.src   = mem_write_en ? TRAP_SRC_STORE_ADDR_MISALIGNED : TRAP_SRC_LOAD_ADDR_MISALIGNED;
      trap.mtval = addr;
    end
  end

endmodule
