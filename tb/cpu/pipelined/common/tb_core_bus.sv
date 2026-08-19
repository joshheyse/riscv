`timescale 1ns / 1ps

// Unified backing store for the core-level testbenches.
//
// `core` presents a single `mem` port. `mem_arbiter` interleaves instruction
// fetches and data accesses behind it, and both L1 caches are pure bypass at
// the core's default (empty) cacheable range, so one slave model serves both
// streams. Requests are discriminated by address: anything at or above
// `MmioBase` is MMIO, everything below it is backing store.
//
// Slow responses are modelled with `mmio_wait`, which adds response latency to
// MMIO accesses. Note what this model deliberately cannot do: refuse a request.
// `mem_arbiter` presents `req.valid` for a single cycle and then stops driving
// it, with no way for a slave to say "not now" -- so a slave that withheld
// acceptance would lose the request outright and wedge the bus. Acceptance is
// therefore unconditional and only the response is delayed.
//
// Response timing at `mmio_wait = 0` matches `rtl/cpu/lib/memory.sv`:
// registered, one cycle after the request.
//
// Tests reach `_store` hierarchically to preload a program or inspect memory:
//
//     _bus._store[32'h0000_0010 >> 2] = 32'h0000_0013;
//
module tb_core_bus
  import riscv_pkg::*;
#(
  parameter int unsigned Words    = 256,
  parameter              InitFile = "",
  parameter mem_addr_t   MmioBase = 32'h1000_0000
) (
  input logic        clk,
  input logic        rst,
        mem_if.slave mem,

  // Extra response latency, in cycles, applied to MMIO accesses only. Holding
  // the data stream while instruction fetch keeps running is how a test creates
  // a memory wait without starving the shared bus.
  input int unsigned mmio_wait,
  input mem_data_t   mmio_read_data,

  // `mmio_write` pulses for one cycle per accepted MMIO store; the captured
  // address and data hold until the next one.
  output logic      mmio_write,
  output mem_addr_t mmio_write_addr,
  output mem_data_t mmio_write_data
);

  localparam int unsigned IndexBits = $clog2(Words);

  mem_data_t                   _store         [0:Words-1];

  logic                        _is_mmio;
  logic        [IndexBits-1:0] _index;
  mem_data_t                   _selected_data;

  int unsigned                 _wait_count;
  mem_data_t                   _pending_data;

  initial begin
    if (InitFile != "") begin
      $readmemh(InitFile, _store);
    end
  end

  assign _is_mmio = mem.req.addr >= MmioBase;
  assign _index = mem.req.addr[IndexBits+1:2];
  assign _selected_data = _is_mmio ? mmio_read_data : _store[_index];

  always_ff @(posedge clk) begin
    if (rst) begin
      mem.rsp         <= '0;
      mmio_write      <= 1'b0;
      mmio_write_addr <= '0;
      mmio_write_data <= '0;
      _wait_count     <= 0;
      _pending_data   <= '0;
    end else begin
      mem.rsp.ready <= 1'b0;
      mmio_write    <= 1'b0;

      if (_wait_count != 0) begin
        // A delayed response is already owed; count it down and deliver.
        _wait_count <= _wait_count - 1;
        if (_wait_count == 1) begin
          mem.rsp.ready     <= 1'b1;
          mem.rsp.read_data <= _pending_data;
        end
      end else if (mem.req.valid) begin
        // Accept unconditionally -- see the note above.
        if (_is_mmio && mmio_wait != 0) begin
          _wait_count   <= mmio_wait;
          _pending_data <= _selected_data;
        end else begin
          mem.rsp.ready     <= 1'b1;
          mem.rsp.read_data <= _selected_data;
        end

        if (mem.req.write_en) begin
          if (_is_mmio) begin
            mmio_write      <= 1'b1;
            mmio_write_addr <= mem.req.addr;
            mmio_write_data <= mem.req.write_data;
          end else begin
            if (mem.req.write_mask[0]) _store[_index][7:0] <= mem.req.write_data[7:0];
            if (mem.req.write_mask[1]) _store[_index][15:8] <= mem.req.write_data[15:8];
            if (mem.req.write_mask[2]) _store[_index][23:16] <= mem.req.write_data[23:16];
            if (mem.req.write_mask[3]) _store[_index][31:24] <= mem.req.write_data[31:24];
          end
        end
      end
    end
  end

endmodule
