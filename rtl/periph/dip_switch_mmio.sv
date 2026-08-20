`timescale 1ns / 1ps

// Synchronized DIP-switch input with per-switch change interrupts.
//
//   DipSwitchAddr   read      synchronized switch state
//   IrqEnableAddr   read/write per-switch interrupt-enable mask
//   IrqPendingAddr  read/W1C  sticky per-switch change flags
//
// A pending bit records a change even while disabled. `meip` asserts whenever
// any pending bit is enabled. A new change wins over a simultaneous W1C clear.
module dip_switch_mmio
  import riscv_pkg::*;
#(
  parameter mem_addr_t   DipSwitchAddr  = 32'h10003000,
  parameter mem_addr_t   IrqEnableAddr  = 32'h10003004,
  parameter mem_addr_t   IrqPendingAddr = 32'h10003008,
  parameter int unsigned NumDipSwitches = 1
) (
  input logic                      clk,
  input logic                      rst,
  input logic [NumDipSwitches-1:0] dip_switch,

  output logic selected,

  mem_if.slave  mem,
  irq_if.source irq
);

  // This slave can always take a request on the cycle it is presented, so
  // acceptance is unconditional. Drive it for real only if that changes.
  assign mem.req_ready = 1'b1;

  localparam int unsigned WordBits = $bits(mem_addr_t);
  initial begin
    assert (NumDipSwitches > 0);
    assert (NumDipSwitches <= WordBits);
    assert (DipSwitchAddr != IrqEnableAddr);
    assert (DipSwitchAddr != IrqPendingAddr);
    assert (IrqEnableAddr != IrqPendingAddr);
  end

  logic [NumDipSwitches-1:0] _irq_en;
  logic [NumDipSwitches-1:0] _pending;
  logic [NumDipSwitches-1:0] _sync_meta;  // metastability-catching stage
  logic [NumDipSwitches-1:0] _sync;  // CPU-clock-domain switch state
  logic [NumDipSwitches-1:0] _previous;
  logic [NumDipSwitches-1:0] _changed;
  logic [NumDipSwitches-1:0] _pending_clear;

  assign selected = (mem.req.addr == DipSwitchAddr || mem.req.addr == IrqEnableAddr || mem.req.addr == IrqPendingAddr);
  assign mem.rsp.valid = mem.req.valid && selected;
  assign _changed = _sync ^ _previous;

  always_comb begin
    mem.rsp.read_data = '0;
    if (mem.req.valid && selected) begin
      if (mem.req.addr == DipSwitchAddr) begin
        mem.rsp.read_data = {{(WordBits - NumDipSwitches) {1'b0}}, _sync};
      end else if (mem.req.addr == IrqEnableAddr) begin
        mem.rsp.read_data = {{(WordBits - NumDipSwitches) {1'b0}}, _irq_en};
      end else if (mem.req.addr == IrqPendingAddr) begin
        mem.rsp.read_data = {{(WordBits - NumDipSwitches) {1'b0}}, _pending};
      end
    end

    _pending_clear = '0;
    if (mem.req.valid && mem.req.write_en && (mem.req.addr == IrqPendingAddr)) begin
      _pending_clear = mem.req.write_data[NumDipSwitches-1:0];
    end

    irq.pending = '0;
    irq.pending.meip = |(_pending & _irq_en);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _irq_en    <= '0;
      _pending   <= '0;
      _sync_meta <= '0;
      _sync      <= '0;
      _previous  <= '0;
    end else begin
      // Physical switches are asynchronous to the CPU clock.
      _sync_meta <= dip_switch;
      _sync      <= _sync_meta;
      _previous  <= _sync;

      if (mem.req.valid && mem.req.write_en && (mem.req.addr == IrqEnableAddr)) begin
        _irq_en <= mem.req.write_data[NumDipSwitches-1:0];
      end

      // A newly observed transition wins over a simultaneous software clear.
      _pending <= (_pending & ~_pending_clear) | _changed;
    end
  end

endmodule
