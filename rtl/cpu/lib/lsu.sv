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
module lsu
  import riscv_pkg::*;
(
  input  mem_addr_t       addr,
  input  mem_data_t       write_data,
  input  mem_size_t       mem_size,
  input  logic            mem_unsigned,
  input  mem_data_t       mem_read_data,
  output mem_data_t       mem_write_data,
  output logic      [3:0] write_mask,
  output mem_data_t       read_data
);

  byte_t _selected_byte;
  half_t _selected_half;

  always_comb begin
    _selected_byte = 8'h0;
    _selected_half = 16'h0;
    read_data = 32'h0;
    write_mask = 4'b0000;
    mem_write_data = 32'h0;
    unique case (mem_size)
      MEM_SIZE_BYTE: begin
        unique case (addr[1:0])
          2'b00: _selected_byte = mem_read_data[7:0];
          2'b01: _selected_byte = mem_read_data[15:8];
          2'b10: _selected_byte = mem_read_data[23:16];
          2'b11: _selected_byte = mem_read_data[31:24];
        endcase
        read_data = mem_unsigned ? {24'b0, _selected_byte} : {{24{_selected_byte[7]}}, _selected_byte};
      end
      MEM_SIZE_HALF: begin
        case (addr[1:0])
          2'b00: _selected_half = mem_read_data[15:0];
          2'b10: _selected_half = mem_read_data[31:16];
          default: begin
          end
        endcase
        read_data = mem_unsigned ? {16'b0, _selected_half} : {{16{_selected_half[15]}}, _selected_half};
      end
      MEM_SIZE_WORD: begin
        read_data = mem_read_data;
      end
    endcase

    unique case (mem_size)
      MEM_SIZE_BYTE: begin
        unique case (addr[1:0])
          2'b00: begin
            mem_write_data = {24'b0, write_data[7:0]};
            write_mask = 4'b0001;
          end
          2'b01: begin
            mem_write_data = {16'b0, write_data[7:0], 8'b0};
            write_mask = 4'b0010;
          end
          2'b10: begin
            mem_write_data = {8'b0, write_data[7:0], 16'b0};
            write_mask = 4'b0100;
          end
          2'b11: begin
            mem_write_data = {write_data[7:0], 24'b0};
            write_mask = 4'b1000;
          end
        endcase
      end
      MEM_SIZE_HALF: begin
        case (addr[1:0])
          2'b00: begin
            mem_write_data = {16'b0, write_data[15:0]};
            write_mask = 4'b0011;
          end
          2'b10: begin
            mem_write_data = {write_data[15:0], 16'b0};
            write_mask = 4'b1100;
          end
          default: begin
          end
        endcase
      end
      MEM_SIZE_WORD: begin
        mem_write_data = write_data;
        write_mask = 4'b1111;
      end
    endcase
  end

  logic _unused_addr_bits;
  assign _unused_addr_bits = |{addr[31:2]};

endmodule
