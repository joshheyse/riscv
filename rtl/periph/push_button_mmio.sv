`timescale 1ns / 1ps

module push_button_mmio
  import riscv_pkg::*;
#(
  parameter word_t PushButtonAddr = '0,
  parameter int unsigned NumPushButtons = 1,
  parameter int unsigned DebounceCycles = 120_000
) (
  input logic clk,
  input logic rst,
  input word_t mem_addr,
  output logic selected,
  output word_t read_data,
  input logic [NumPushButtons-1:0] push_button
);

  localparam int unsigned WordBits = $bits(mem_addr);
  localparam int unsigned DebounceCounterBits = $clog2(DebounceCycles + 1);
  localparam logic [DebounceCounterBits-1:0] DebounceCounterMax = DebounceCounterBits'(DebounceCycles - 1);
  localparam logic [DebounceCounterBits-1:0] DebounceCounterInc = DebounceCounterBits'(1);

  initial begin
    assert (NumPushButtons < WordBits);
    assert (DebounceCycles > 1);
  end

  logic [NumPushButtons-1:0] _sync_0;
  logic [NumPushButtons-1:0] _sync_1;
  logic [NumPushButtons-1:0] _debounced_button;
  logic [DebounceCounterBits-1:0] _counter;

  assign selected  = (mem_addr == PushButtonAddr);
  assign read_data = {{(WordBits - NumPushButtons) {1'b0}}, _debounced_button};

  always_ff @(posedge clk) begin
    if (rst) begin
      _sync_0 <= 0;
      _sync_1 <= 0;
      _counter <= 0;
      _debounced_button <= 0;
    end else begin
      _sync_0 <= push_button;
      _sync_1 <= _sync_0;

      if (_sync_1 == _debounced_button) begin
        _counter <= '0;
      end else if (_counter == DebounceCounterMax) begin
        _debounced_button <= _sync_1;
        _counter <= '0;
      end else begin
        _counter <= _counter + DebounceCounterInc;
      end
    end
  end

endmodule
