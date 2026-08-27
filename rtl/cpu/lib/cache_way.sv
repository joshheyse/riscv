`timescale 1ns / 1ps

module cache_way
  import riscv_pkg::*;
(
  input logic            clk,
  input logic            rst,
  input set_index_t      set,
  input tag_t            lookup_tag,
  input word_index_t     word_index,
  input logic            data_read_en,
  input logic            data_write_en,
  input mem_data_t       write_data,
  input mem_write_mask_t write_mask,
  input cache_meta_op_e  meta_op,
  input tag_t            install_tag,

  output logic      hit,
  output logic      valid,
  output logic      dirty,
  output tag_t      stored_tag,
  output mem_data_t read_data
);

  // Reset metadata only. The word array has the synchronous ports required for
  // ECP5 block RAM and deliberately has no reset assignment.
  (* ram_style = "block" *)
  logic        [            31:0] _data      [CacheNumSets*CacheWordsPerLine];
  tag_t                           _tags      [                  CacheNumSets];
  logic        [CacheNumSets-1:0] _valid;
  logic        [CacheNumSets-1:0] _dirty;
  data_index_t                    _data_addr;

  assert property (@(posedge clk) disable iff (rst) !(data_read_en && data_write_en));

  always_comb begin
    _data_addr = {set, word_index};
    hit        = _valid[set] && (_tags[set] == lookup_tag);
    valid      = _valid[set];
    dirty      = _dirty[set];
    stored_tag = _tags[set];
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _valid <= '0;
      _dirty <= '0;
    end else begin

      if (data_read_en) begin
        read_data <= _data[_data_addr];
      end else if (data_write_en) begin
        for (int unsigned byte_idx = 0; byte_idx < 4; byte_idx++) begin
          if (write_mask[byte_idx]) begin
            _data[_data_addr][byte_idx*8+:8] <= write_data[byte_idx*8+:8];
          end
        end
      end

      unique case (meta_op)
        META_NONE: begin
        end
        META_INSTALL: begin
          _tags[set]  <= install_tag;
          _valid[set] <= 1'b1;
          _dirty[set] <= 1'b0;
        end
        META_MARK_DIRTY: begin
          _dirty[set] <= 1'b1;
        end
        META_CLEAR_DIRTY: begin
          _dirty[set] <= 1'b0;
        end
        META_INVALIDATE: begin
          _valid[set] <= 1'b0;
          _dirty[set] <= 1'b0;
        end
      endcase
    end

  end


endmodule
