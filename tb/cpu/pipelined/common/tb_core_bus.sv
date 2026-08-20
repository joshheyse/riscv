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
// MMIO accesses. The model refuses new requests on `req_ready` while a delayed
// response is still owed, and holds an answered response until the master takes
// it on `rsp_ready` -- the single-outstanding rule, on both channels.
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
  logic                        _accept;
  logic                        _holding;

  initial begin
    if (InitFile != "") begin
      $readmemh(InitFile, _store);
    end
  end

  assign _is_mmio = mem.req.addr >= MmioBase;
  assign _index = mem.req.addr[IndexBits+1:2];
  assign _selected_data = _is_mmio ? mmio_read_data : _store[_index];

  // Accept a request whenever nothing is owed. Refusing costs nothing now: the
  // master simply keeps the request presented until it is taken.
  // Nothing is owed, and no answered response is still waiting to be taken.
  assign _holding = mem.rsp.valid && !mem.rsp_ready;
  assign mem.req_ready = (_wait_count == 0) && !_holding;
  assign _accept = mem.req.valid && mem.req_ready;

  always_ff @(posedge clk) begin
    if (rst) begin
      mem.rsp         <= '0;
      mmio_write      <= 1'b0;
      mmio_write_addr <= '0;
      mmio_write_data <= '0;
      _wait_count     <= 0;
      _pending_data   <= '0;
    end else if (_holding) begin
      // A response the master has not taken yet must stay exactly as it is.
      mmio_write <= 1'b0;
    end else begin
      mem.rsp.valid <= 1'b0;
      mmio_write    <= 1'b0;

      if (_wait_count != 0) begin
        // A delayed response is already owed; count it down and deliver.
        _wait_count <= _wait_count - 1;
        if (_wait_count == 1) begin
          mem.rsp.valid     <= 1'b1;
          mem.rsp.read_data <= _pending_data;
        end
      end else if (_accept) begin
        if (_is_mmio && mmio_wait != 0) begin
          _wait_count   <= mmio_wait;
          _pending_data <= _selected_data;
        end else begin
          mem.rsp.valid     <= 1'b1;
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
