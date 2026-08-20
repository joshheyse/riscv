`timescale 1ns / 1ps

// Debounced push-button input with per-button press interrupts.
//
//   PushButtonAddr  read       debounced button state
//   IrqEnableAddr   read/write per-button interrupt-enable mask
//   IrqPendingAddr  read/W1C   sticky per-button press flags
//
// Only a debounced rising edge records an event. Releases update the visible
// state without setting pending. A new press wins over a simultaneous clear.
module push_button_mmio
  import riscv_pkg::*;
#(
  parameter mem_addr_t   PushButtonAddr = 32'h10003010,
  parameter mem_addr_t   IrqEnableAddr  = 32'h10003014,
  parameter mem_addr_t   IrqPendingAddr = 32'h10003018,
  parameter int unsigned NumPushButtons = 1,
  parameter int unsigned DebounceCycles = 120_000
) (
  input logic                      clk,
  input logic                      rst,
  input logic [NumPushButtons-1:0] push_button,

  output logic selected,

  mem_if.slave  mem,
  irq_if.source irq
);


  // This slave can always take a request on the cycle it is presented, so
  // acceptance is unconditional. Drive it for real only if that changes.
  assign mem.req_ready = 1'b1;

  localparam int unsigned WordBits = $bits(mem_addr_t);
  localparam int unsigned DebounceCounterBits = $clog2(DebounceCycles + 1);
  localparam logic [DebounceCounterBits-1:0] DebounceCounterMax = DebounceCounterBits'(DebounceCycles - 1);
  localparam logic [DebounceCounterBits-1:0] DebounceCounterInc = DebounceCounterBits'(1);

  initial begin
    assert (NumPushButtons > 0);
    assert (NumPushButtons <= WordBits);
    assert (DebounceCycles > 1);
    assert (PushButtonAddr != IrqEnableAddr);
    assert (PushButtonAddr != IrqPendingAddr);
    assert (IrqEnableAddr != IrqPendingAddr);
  end

  logic [     NumPushButtons-1:0] _sync_0;
  logic [     NumPushButtons-1:0] _sync_1;
  logic [     NumPushButtons-1:0] _debounced_button;
  logic [     NumPushButtons-1:0] _previous;
  logic [     NumPushButtons-1:0] _pressed;
  logic [     NumPushButtons-1:0] _irq_en;
  logic [     NumPushButtons-1:0] _pending;
  logic [     NumPushButtons-1:0] _pending_clear;
  logic [DebounceCounterBits-1:0] _counter;

  assign selected = (mem.req.addr == PushButtonAddr || mem.req.addr == IrqEnableAddr || mem.req.addr == IrqPendingAddr);
  assign mem.rsp.valid = mem.req.valid && selected;
  assign _pressed = _debounced_button & ~_previous;

  always_comb begin
    mem.rsp.read_data = '0;
    if (mem.req.valid && selected) begin
      if (mem.req.addr == PushButtonAddr) begin
        mem.rsp.read_data = {{(WordBits - NumPushButtons) {1'b0}}, _debounced_button};
      end else if (mem.req.addr == IrqEnableAddr) begin
        mem.rsp.read_data = {{(WordBits - NumPushButtons) {1'b0}}, _irq_en};
      end else if (mem.req.addr == IrqPendingAddr) begin
        mem.rsp.read_data = {{(WordBits - NumPushButtons) {1'b0}}, _pending};
      end
    end

    _pending_clear = '0;
    if (mem.req.valid && mem.req.write_en && (mem.req.addr == IrqPendingAddr)) begin
      _pending_clear = mem.req.write_data[NumPushButtons-1:0];
    end

    irq.pending = '0;
    irq.pending.meip = |(_pending & _irq_en);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _sync_0 <= '0;
      _sync_1 <= '0;
      _counter <= '0;
      _debounced_button <= '0;
      _previous <= '0;
      _irq_en <= '0;
      _pending <= '0;
    end else begin
      _sync_0   <= push_button;
      _sync_1   <= _sync_0;
      _previous <= _debounced_button;

      if (_sync_1 == _debounced_button) begin
        _counter <= '0;
      end else if (_counter == DebounceCounterMax) begin
        _debounced_button <= _sync_1;
        _counter <= '0;
      end else begin
        _counter <= _counter + DebounceCounterInc;
      end

      if (mem.req.valid && mem.req.write_en && (mem.req.addr == IrqEnableAddr)) begin
        _irq_en <= mem.req.write_data[NumPushButtons-1:0];
      end

      _pending <= (_pending & ~_pending_clear) | _pressed;
    end
  end

endmodule
