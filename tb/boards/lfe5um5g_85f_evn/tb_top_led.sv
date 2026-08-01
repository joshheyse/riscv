`timescale 1ns / 1ps

module tb_top_led;
  localparam string ProgramFile =
      "/home/josh/code/riscv-soc/build/boards/lfe5um5g_85f_evn/apps/led_skip/led_skip.mem";

  logic       _clk_12mhz;
  logic       _rst_n;
  logic       _uart_tx;
  logic [7:0] _led_n;
  logic [7:0] _dip_switch_n;
  logic       _push_button_n;
  tri   [7:0] gpio;
  logic       _spi_sck;
  logic       _spi_mosi;
  logic       _spi_miso;
  logic       _spi_cs_n;
  tri1        _i2c_sda;
  tri1        _i2c_scl;
  logic       _unused_outputs;
  int         _errors;

  assign _unused_outputs = _uart_tx | _spi_sck | _spi_mosi | _spi_cs_n | (|gpio) | _i2c_sda | _i2c_scl;

  top #(
    .ImemInitFile(ProgramFile),
    .PowerOnResetCycles(4)
  ) _dut (
    .clk_12mhz(_clk_12mhz),
    .rst_n(_rst_n),
    .uart_tx(_uart_tx),
    .led_n(_led_n),
    .dip_switch_n(_dip_switch_n),
    .push_button_n(_push_button_n),
    .gpio(gpio),
    .spi_sck(_spi_sck),
    .spi_mosi(_spi_mosi),
    .spi_miso(_spi_miso),
    .spi_cs_n(_spi_cs_n),
    .i2c_sda(_i2c_sda),
    .i2c_scl(_i2c_scl)
  );

  initial begin
    _clk_12mhz = 1'b0;
    forever #5 _clk_12mhz = ~_clk_12mhz;
  end

  initial begin
    _errors        = 0;
    _rst_n         = 1'b1;
    _dip_switch_n  = 8'hff;
    _push_button_n = 1'b1;
    _spi_miso      = 1'b0;

    repeat (12) @(posedge _clk_12mhz);

    if (_led_n !== 8'b1111_1110) begin
      $error("expected LED0 on after first MMIO store, got led_n=%b", _led_n);
      _errors++;
    end

    if (_errors != 0) begin
      $fatal(1, "tb_top_led: FAIL (%0d errors)", _errors);
    end

    $display("tb_top_led: PASS");
    $finish;
  end

  initial begin
    #1000;
    $fatal(1, "tb_top_led: watchdog timeout");
  end
endmodule
