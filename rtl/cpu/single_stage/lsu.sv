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
module lsu #(
  parameter int unsigned DepthWords = 512,
  parameter InitFile = ""
) (
  input logic clk,
  input logic mem_write,
  input riscv_pkg::word_t addr,
  input riscv_pkg::word_t write_data,
  input riscv_pkg::mem_size_t mem_size,
  input logic mem_unsigned,
  output riscv_pkg::word_t read_data
);

  logic [31:0] memory[0:DepthWords-1];
  initial begin
    if (InitFile != "") begin
      $readmemh(InitFile, memory);
    end
  end

  localparam int unsigned IndexBits = $clog2(DepthWords);
  logic [IndexBits-1:0] word_index;

  riscv_pkg::word_t word;
  riscv_pkg::byte_t selected_byte;
  riscv_pkg::half_t selected_half;

  assign word_index = addr[IndexBits+1:2];
  assign word = memory[word_index];

  always_comb begin
    selected_byte = 8'h0;
    selected_half = 16'h0;
    read_data = 32'h0;
    unique case (mem_size)
      riscv_pkg::MEM_SIZE_BYTE: begin
        unique case (addr[1:0])
          2'b00: selected_byte = word[7:0];
          2'b01: selected_byte = word[15:8];
          2'b10: selected_byte = word[23:16];
          2'b11: selected_byte = word[31:24];
        endcase
        read_data = mem_unsigned ? {24'b0, selected_byte} : {{24{selected_byte[7]}}, selected_byte};
      end
      riscv_pkg::MEM_SIZE_HALF: begin
        case (addr[1:0])
          2'b00: selected_half = word[15:0];
          2'b10: selected_half = word[31:16];
          default: begin
          end
        endcase
        read_data = mem_unsigned ? {16'b0, selected_half} : {{16{selected_half[15]}}, selected_half};
      end
      riscv_pkg::MEM_SIZE_WORD: begin
        read_data = word;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (mem_write) begin
      unique case (mem_size)
        riscv_pkg::MEM_SIZE_BYTE: begin
          unique case (addr[1:0])
            2'b00: memory[word_index] <= {memory[word_index][31:8], write_data[7:0]};
            2'b01:
            memory[word_index] <= {
              memory[word_index][31:16], write_data[7:0], memory[word_index][7:0]
            };
            2'b10:
            memory[word_index] <= {
              memory[word_index][31:24], write_data[7:0], memory[word_index][15:0]
            };
            2'b11: memory[word_index] <= {write_data[7:0], memory[word_index][23:0]};
          endcase
        end
        riscv_pkg::MEM_SIZE_HALF: begin
          case (addr[1:0])
            2'b00: memory[word_index] <= {memory[word_index][31:16], write_data[15:0]};
            2'b10: memory[word_index] <= {write_data[15:0], memory[word_index][15:0]};
            default: begin
            end
          endcase
        end
        riscv_pkg::MEM_SIZE_WORD: begin
          memory[word_index] <= write_data;
        end
      endcase
    end else begin
    end
  end

  logic unused_addr_bits;
  assign unused_addr_bits = |{addr[31:IndexBits+2]};

endmodule
