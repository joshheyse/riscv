`timescale 1ns / 1ps

// Word-only load/store unit.
//
// This is the first simple data memory for the single-cycle core. It supports
// full-word loads and stores only (`lw`/`sw` behavior). Byte and halfword
// accesses will need extra size/sign controls later.
//
// Reads are combinational so a load can produce writeback data in the same
// single-cycle instruction. Writes occur on the rising clock edge.
//
//   addr byte range       RAM index
//   -------------------   -----------------------
//   0x0000_0000 + 4*N     addr[IndexBits+1:2] = N
//
// As with imem, low alignment bits and high unmapped bits are intentionally
// ignored for this tiny word-addressed memory.
//
module lsu (
  input riscv_pkg::word_t addr,
  input riscv_pkg::word_t write_data,
  input riscv_pkg::mem_size_t mem_size,
  input logic mem_unsigned,
  input riscv_pkg::word_t read_mem,
  output riscv_pkg::word_t write_mem,
  output riscv_pkg::word_t read_data
);

  riscv_pkg::byte_t selected_byte;
  riscv_pkg::half_t selected_half;

  always_comb begin
    selected_byte = 8'h0;
    selected_half = 16'h0;
    read_data = 32'h0;
    unique case (mem_size)
      riscv_pkg::MEM_SIZE_BYTE: begin
        unique case (addr[1:0])
          2'b00: selected_byte = read_mem[7:0];
          2'b01: selected_byte = read_mem[15:8];
          2'b10: selected_byte = read_mem[23:16];
          2'b11: selected_byte = read_mem[31:24];
        endcase
        read_data = mem_unsigned ? {24'b0, selected_byte} : {{24{selected_byte[7]}}, selected_byte};
      end
      riscv_pkg::MEM_SIZE_HALF: begin
        case (addr[1:0])
          2'b00: selected_half = read_mem[15:0];
          2'b10: selected_half = read_mem[31:16];
          default: begin
          end
        endcase
        read_data = mem_unsigned ? {16'b0, selected_half} : {{16{selected_half[15]}}, selected_half};
      end
      riscv_pkg::MEM_SIZE_WORD: begin
        read_data = read_mem;
      end
    endcase

    write_mem = read_mem;
    unique case (mem_size)
      riscv_pkg::MEM_SIZE_BYTE: begin
        unique case (addr[1:0])
          2'b00: write_mem = {write_mem[31:8], write_data[7:0]};
          2'b01: write_mem = {write_mem[31:16], write_data[7:0], write_mem[7:0]};
          2'b10: write_mem = {write_mem[31:24], write_data[7:0], write_mem[15:0]};
          2'b11: write_mem = {write_data[7:0], write_mem[23:0]};
        endcase
      end
      riscv_pkg::MEM_SIZE_HALF: begin
        case (addr[1:0])
          2'b00: write_mem = {write_mem[31:16], write_data[15:0]};
          2'b10: write_mem = {write_data[15:0], write_mem[15:0]};
          default: begin
          end
        endcase
      end
      riscv_pkg::MEM_SIZE_WORD: begin
        write_mem = write_data;
      end
    endcase
  end

  logic unused_addr_bits;
  assign unused_addr_bits = |{addr[31:2]};

endmodule
