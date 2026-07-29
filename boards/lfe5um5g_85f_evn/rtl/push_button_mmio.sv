`timescale 1ns / 1ps

module push_button_mmio #(
  parameter riscv_pkg::word_t PushButtonAddr = memmap_pkg::PushButtonAddr,
  parameter int unsigned NumPushButtons = memmap_pkg::NumPushButtons,
  parameter int unsigned DebounceCycles = 120_000
) (
  input logic clk,
  input logic rst,
  input riscv_pkg::word_t mem_addr,
  output logic selected,
  output riscv_pkg::word_t read_data,
  input logic [NumPushButtons-1:0] push_button
);

  localparam int unsigned WordBits = $bits(riscv_pkg::word_t);
  localparam int unsigned DebounceCounterBits = $clog2(DebounceCycles + 1);
  localparam logic [DebounceCounterBits-1:0] DebounceCounterMax = DebounceCounterBits'(DebounceCycles - 1);
  localparam logic [DebounceCounterBits-1:0] DebounceCounterInc = DebounceCounterBits'(1);

  initial begin
    assert (NumPushButtons < WordBits);
    assert (DebounceCycles > 1);
  end

  logic [NumPushButtons-1:0] sync_0;
  logic [NumPushButtons-1:0] sync_1;
  logic [NumPushButtons-1:0] debounced_button;
  logic [DebounceCounterBits-1:0] counter;

  assign selected  = (mem_addr == PushButtonAddr);
  assign read_data = {{(WordBits - NumPushButtons) {1'b0}}, debounced_button};

  always_ff @(posedge clk) begin
    if (rst) begin
      sync_0 <= 0;
      sync_1 <= 0;
      counter <= 0;
      debounced_button <= 0;
    end else begin
      sync_0 <= push_button;
      sync_1 <= sync_0;

      if (sync_1 == debounced_button) begin
        counter <= '0;
      end else if (counter == DebounceCounterMax) begin
        debounced_button <= sync_1;
        counter <= '0;
      end else begin
        counter <= counter + DebounceCounterInc;
      end
    end
  end

endmodule
