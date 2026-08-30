`timescale 1ns / 1ps

// Incrementally decodes the raw PMP CSRs into the region representation used
// by the access checks.  The caller must quiesce memory accesses before
// asserting rebuild_start; once a rebuild starts it runs to completion and
// cannot be cancelled.
module pmp_decoder
  import riscv_pkg::*;
  import pmp_pkg::*;
(
  input logic               clk,
  input logic               rst,
  input pmp_state_t         raw_state,
  input csr_addr_raw_t      write_addr,
  input csr_data_t          write_data,
  input logic               rebuild_start,
  input logic               rebuild_commit,
  output pmp_region_state_t regions,
  output pmp_state_t         rebuild_candidate,
  output logic               rebuild_wait,
  output logic               rebuild_ready
);

  localparam int unsigned PmpIndexBits = index_width(PmpNumEntries);
  typedef logic [PmpIndexBits-1:0] pmp_index_t;
  localparam pmp_index_t LastEntryIndex = pmp_index_t'(PmpNumEntries - 1);

  typedef enum logic [1:0] {
    REBUILD_IDLE,
    REBUILD_BUILD,
    REBUILD_READY
  } rebuild_state_e;

  pmp_region_state_t _regions;
  pmp_state_t        _rebuild_candidate;
  pmp_region_t       _region_build;
  pmp_addr_t         _rebuild_predecessor_addr;
  pmp_index_t        _rebuild_index;
  rebuild_state_e     _state;

  assign regions = _regions;
  assign rebuild_candidate = _rebuild_candidate;

  always_comb begin
    _rebuild_predecessor_addr = '0;
    if (_rebuild_index != '0) begin
      _rebuild_predecessor_addr =
          _rebuild_candidate.addr[_rebuild_index - 1'b1];
    end
    _region_build = pmp_decode_region(
        _rebuild_candidate.addr[_rebuild_index],
        _rebuild_predecessor_addr,
        _rebuild_candidate.cfg[_rebuild_index]);
  end

  always_comb begin
    // The start indication may remain high while the CSR instruction is held
    // in ID/EX. Qualify it with IDLE so READY can release the pipeline for the
    // commit edge.
    rebuild_wait = ((_state == REBUILD_IDLE) && rebuild_start) ||
        (_state == REBUILD_BUILD);
    rebuild_ready = _state == REBUILD_READY;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _regions <= '0;
      _rebuild_index <= '0;
      _state <= REBUILD_IDLE;
    end else begin
      case (_state)
        REBUILD_IDLE: begin
          if (rebuild_start) begin
            _rebuild_candidate <= pmp_state_after_write(raw_state, write_addr, write_data);
            _rebuild_index <= '0;
            _state <= REBUILD_BUILD;
          end
        end
        REBUILD_BUILD: begin
          _regions.entries[_rebuild_index] <= _region_build;
          if (_rebuild_index == LastEntryIndex) begin
            _state <= REBUILD_READY;
          end else begin
            _rebuild_index <= _rebuild_index + 1'b1;
          end
        end
        REBUILD_READY: begin
          if (rebuild_commit) begin
            _state <= REBUILD_IDLE;
          end
        end
        default: begin
          _state <= REBUILD_IDLE;
        end
      endcase
    end
  end

endmodule
