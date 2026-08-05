`timescale 1ns / 1ps

module tb_spi_mmio
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned ClocksPerHalfBit =
      board_constants_pkg::ClockHz / (2 * board_constants_pkg::SpiHz);
  localparam int unsigned TimeoutCycles = 400;
  localparam word_t DataAddr = 32'h1000_4000;
  localparam word_t ControlAddr = 32'h1000_4004;
  localparam word_t StatusAddr = 32'h1000_4008;
  localparam logic [7:0] TxByte = 8'ha5;
  localparam logic [7:0] RxByte = 8'h3c;

  logic            _clk;
  logic            _rst;
  logic            _mem_valid;
  logic            _mem_write_en;
  word_t           _mem_addr;
  word_t           _mem_write_data;
  mem_write_mask_t _mem_write_mask;
  logic            _selected;
  logic            _mem_ready;
  word_t           _read_data;
  logic            _spi_sck;
  logic            _spi_mosi;
  logic            _spi_miso;
  logic            _spi_cs_n;

  int unsigned     errors = 0;
  int unsigned     checks = 0;
  /* verilator lint_off UNUSEDSIGNAL */
  logic            _mem_ready_observed;
  /* verilator lint_on UNUSEDSIGNAL */
  assign _mem_ready_observed = _mem_ready;

  spi_mmio #(
    .DataAddr(DataAddr),
    .ControlAddr(ControlAddr),
    .StatusAddr(StatusAddr),
    .ClocksPerHalfBit(ClocksPerHalfBit)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .mem_valid(_mem_valid),
    .mem_write_en(_mem_write_en),
    .mem_addr(_mem_addr),
    .mem_write_data(_mem_write_data),
    .mem_write_mask(_mem_write_mask),
    .selected(_selected),
    .mem_ready(_mem_ready),
    .mem_read_data(_read_data),
    .spi_sck(_spi_sck),
    .spi_mosi(_spi_mosi),
    .spi_miso(_spi_miso),
    .spi_cs_n(_spi_cs_n)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  task automatic expect_bit(input logic got, input logic exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic set_read_addr(input word_t addr);
    @(negedge _clk);
    _mem_valid = 1'b1;
    _mem_write_en = 1'b0;
    _mem_addr = addr;
    _mem_write_mask = '0;
    #1;
  endtask

  task automatic write_mmio(input word_t addr, input word_t data);
    @(negedge _clk);
    _mem_addr       = addr;
    _mem_write_data = data;
    _mem_write_mask = 4'b1111;
    _mem_valid      = 1'b1;
    _mem_write_en   = 1'b1;
    @(posedge _clk);
    #1;
    _mem_write_en   = 1'b0;
    _mem_write_mask = '0;
  endtask

  task automatic expect_idle(input string what);
    expect_bit(_spi_sck, 1'b0, {what, ": sck idle low"});
    expect_bit(_spi_mosi, 1'b0, {what, ": mosi idle low"});
    expect_bit(_spi_cs_n, 1'b1, {what, ": cs inactive"});
  endtask

  task automatic expect_status_busy(input logic exp, input string what);
    set_read_addr(StatusAddr);
    expect_bit(_selected, 1'b1, "status address selected");
    expect_word(_read_data, {31'b0, exp}, what);
  endtask

  task automatic expect_spi_bit(input logic [2:0] bit_index);
    logic miso_sampled;

    // After the first bit, the previous check leaves the FSM at the end of
    // SCK_LOW. One extra clock advances into SETUP for the next bit.
    if (bit_index != 3'd7) begin
      @(posedge _clk);
      #1;
    end

    // SETUP state: CS active, SCK low, MOSI stable before sample edge.
    #1;
    expect_bit(_spi_cs_n, 1'b0, "cs active during setup");
    expect_bit(_spi_sck, 1'b0, "sck low during setup");
    expect_bit(_spi_mosi, TxByte[bit_index], "mosi bit during setup");

    // SCK_HIGH state: hold the sample clock high for the configured divider.
    _spi_miso = RxByte[bit_index];
    miso_sampled = 1'b0;
    for (int unsigned cycle = 0; cycle < ClocksPerHalfBit; cycle++) begin
      @(posedge _clk);
      #1;
      expect_bit(_spi_cs_n, 1'b0, "cs active during high");
      expect_bit(_spi_sck, 1'b1, "sck high during sample");
      expect_bit(_spi_mosi, TxByte[bit_index], "mosi stable during high");
      if (cycle == 0) begin
        miso_sampled = 1'b1;
      end
    end
    expect_bit(miso_sampled, 1'b1, "miso sample cycle observed");

    // SCK_LOW state: hold the clock low for the configured divider.
    for (int unsigned cycle = 0; cycle < ClocksPerHalfBit; cycle++) begin
      @(posedge _clk);
      #1;
      expect_bit(_spi_cs_n, 1'b0, "cs active during low");
      expect_bit(_spi_sck, 1'b0, "sck low after sample");
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_spi_mmio);
    end

    _rst            = 1'b1;
    _mem_valid      = 1'b0;
    _mem_write_en   = 1'b0;
    _mem_addr       = '0;
    _mem_write_data = '0;
    _mem_write_mask = '0;
    _spi_miso       = 1'b0;

    repeat (2) @(posedge _clk);
    #1;
    expect_bit(_selected, 1'b0, "reset unmapped address not selected");
    expect_word(_read_data, '0, "reset unmapped read is zero");
    expect_idle("reset");

    @(negedge _clk);
    _rst = 1'b0;

    set_read_addr(DataAddr);
    expect_bit(_selected, 1'b1, "data address selected");
    expect_word(_read_data, 32'h0000_0000, "initial rx data is zero");

    set_read_addr(ControlAddr);
    expect_bit(_selected, 1'b1, "control address selected");
    expect_word(_read_data, 32'h0000_0000, "control read is zero");

    expect_status_busy(1'b0, "idle status not busy");

    write_mmio(DataAddr, {24'hff_ffff, TxByte});
    set_read_addr(DataAddr);
    expect_word(_read_data, 32'h0000_0000, "data write does not change rx data");

    write_mmio(ControlAddr, 32'h0000_0001);
    expect_status_busy(1'b1, "start write makes SPI busy");

    expect_spi_bit(3'd7);
    expect_spi_bit(3'd6);
    expect_spi_bit(3'd5);
    expect_spi_bit(3'd4);
    expect_spi_bit(3'd3);
    expect_spi_bit(3'd2);
    expect_spi_bit(3'd1);
    expect_spi_bit(3'd0);

    @(posedge _clk);
    #1;
    expect_bit(_spi_cs_n, 1'b1, "cs inactive during done");
    expect_bit(_spi_sck, 1'b0, "sck idle low during done");

    @(posedge _clk);
    #1;
    expect_idle("done");
    expect_status_busy(1'b0, "status not busy after transfer");

    set_read_addr(DataAddr);
    expect_word(_read_data, {24'b0, RxByte}, "rx data read returns sampled byte");

    set_read_addr(32'h2000_0000);
    expect_bit(_selected, 1'b0, "unmapped address not selected");
    expect_word(_read_data, 32'h0000_0000, "unmapped read returns zero");

    if (errors == 0) begin
      $display("tb_spi_mmio: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_spi_mmio: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_spi_mmio: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
