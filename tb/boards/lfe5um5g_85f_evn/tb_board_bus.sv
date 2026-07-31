`timescale 1ns / 1ps

module tb_board_bus
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned PushButtonDebounceCycles = 120_000;
  localparam int unsigned TimeoutCycles = PushButtonDebounceCycles + 1_000;

  logic clk;
  logic rst;
  logic [7:0] led;
  logic [7:0] dip_switch;
  logic push_button;
  logic uart_tx;
  logic spi_sck;
  logic spi_mosi;
  logic spi_miso;
  logic spi_cs_n;
  logic i2c_sda_in;
  logic i2c_sda_drive_low;
  logic i2c_scl_in;
  logic i2c_scl_drive_low;
  logic [board_constants_pkg::NumGpio-1:0] gpio_in;
  logic [board_constants_pkg::NumGpio-1:0] gpio_out;
  logic [board_constants_pkg::NumGpio-1:0] gpio_oe;
  logic dbus_valid;
  logic dbus_write;
  logic dbus_ready;
  word_t dbus_addr;
  word_t dbus_write_data;
  word_t dbus_read_data;
  mem_size_t dbus_size;
  logic dbus_unsigned;

  int unsigned errors = 0;
  int unsigned checks = 0;

  board_bus #(
    .DmemDepthWords(16)
  ) dut (
    .clk(clk),
    .rst(rst),
    .led(led),
    .dip_switch(dip_switch),
    .push_button(push_button),
    .uart_tx(uart_tx),
    .spi_sck(spi_sck),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso),
    .spi_cs_n(spi_cs_n),
    .i2c_sda_in(i2c_sda_in),
    .i2c_sda_drive_low(i2c_sda_drive_low),
    .i2c_scl_in(i2c_scl_in),
    .i2c_scl_drive_low(i2c_scl_drive_low),
    .gpio_in(gpio_in),
    .gpio_out(gpio_out),
    .gpio_oe(gpio_oe),
    .dbus_valid(dbus_valid),
    .dbus_write(dbus_write),
    .dbus_addr(dbus_addr),
    .dbus_write_data(dbus_write_data),
    .dbus_read_data(dbus_read_data),
    .dbus_ready(dbus_ready),
    .dbus_size(dbus_size),
    .dbus_unsigned(dbus_unsigned)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  task automatic expect_bit(input logic got, input logic exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic expect_byte(input logic [7:0] got, input logic [7:0] exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%02h, expected 0x%02h", $time, what, got, exp);
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
    @(negedge clk);
    dbus_valid = 1'b1;
    dbus_write = 1'b0;
    dbus_addr  = addr;
    @(posedge clk);
    #1;
    expect_bit(dbus_ready, 1'b1, "read ready");
    dbus_valid = 1'b0;
  endtask

  task automatic write_bus(input word_t addr, input word_t data);
    @(negedge clk);
    dbus_valid      = 1'b1;
    dbus_addr       = addr;
    dbus_write_data = data;
    dbus_write      = 1'b1;
    @(posedge clk);
    #1;
    expect_bit(dbus_ready, 1'b1, "write ready");
    dbus_valid = 1'b0;
    dbus_write = 1'b0;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_board_bus);
    end

    rst             = 1'b1;
    dbus_valid      = 1'b0;
    dbus_write      = 1'b0;
    dbus_addr       = '0;
    dbus_write_data = '0;
    dbus_size       = MEM_SIZE_WORD;
    dbus_unsigned   = 1'b0;
    dip_switch      = 8'h00;
    push_button     = 1'b0;
    spi_miso        = 1'b0;
    i2c_sda_in      = 1'b1;
    i2c_scl_in      = 1'b1;
    gpio_in         = '0;

    repeat (2) @(posedge clk);
    #1;
    expect_byte(led, 8'h00, "reset clears LEDs");
    expect_byte(gpio_out, 8'h00, "reset clears GPIO output latch");
    expect_byte(gpio_oe, 8'h00, "reset clears GPIO output enable");
    expect_bit(uart_tx, 1'b1, "reset leaves UART idle high");
    expect_bit(spi_sck, 1'b0, "reset leaves SPI clock idle low");
    expect_bit(spi_mosi, 1'b0, "reset leaves SPI MOSI idle low");
    expect_bit(spi_cs_n, 1'b1, "reset leaves SPI chip select inactive");
    expect_bit(i2c_sda_drive_low, 1'b0, "reset releases I2C SDA");
    expect_bit(i2c_scl_drive_low, 1'b0, "reset releases I2C SCL");

    @(negedge clk);
    rst = 1'b0;

    set_read_addr(32'h2000_0000);
    expect_word(dbus_read_data, '0, "unmapped read returns zero");

    write_bus(board_constants_pkg::LedAddr, 32'h0000_00a5);
    expect_byte(led, 8'ha5, "LED write reaches LED MMIO");
    set_read_addr(board_constants_pkg::LedAddr);
    expect_word(dbus_read_data, 32'h0000_00a5, "LED read routes through board bus");

    write_bus(32'h2000_0000, 32'h0000_005a);
    expect_byte(led, 8'ha5, "unmapped write does not change LED MMIO");
    set_read_addr(32'h2000_0000);
    expect_word(dbus_read_data, '0, "unmapped read still returns zero after write");

    write_bus(board_constants_pkg::DmemBase + 32'h0000_0004, 32'hdead_beef);
    set_read_addr(board_constants_pkg::DmemBase + 32'h0000_0004);
    expect_word(dbus_read_data, 32'hdead_beef, "DMEM write/read routes to LSU");

    write_bus(board_constants_pkg::LedAddr, 32'h0000_0011);
    set_read_addr(board_constants_pkg::DmemBase + 32'h0000_0004);
    expect_word(dbus_read_data, 32'hdead_beef, "LED write does not change DMEM");

    dip_switch = 8'hc3;
    set_read_addr(board_constants_pkg::DipSwitchAddr);
    expect_word(dbus_read_data, 32'h0000_00c3, "DIP switch read routes through board bus");

    push_button = 1'b1;
    repeat (PushButtonDebounceCycles + 3) @(posedge clk);
    #1;
    set_read_addr(board_constants_pkg::PushButtonAddr);
    expect_word(dbus_read_data, 32'h0000_0001, "push button read routes through board bus");

    gpio_in = 8'h3c;
    set_read_addr(board_constants_pkg::GpioDataInAddr);
    expect_word(dbus_read_data, 32'h0000_003c, "GPIO input read routes through board bus");

    write_bus(board_constants_pkg::GpioDataOutAddr, 32'h0000_0055);
    expect_byte(gpio_out, 8'h55, "GPIO output write reaches GPIO MMIO");
    set_read_addr(board_constants_pkg::GpioDataOutAddr);
    expect_word(dbus_read_data, 32'h0000_0055, "GPIO output read routes through board bus");

    write_bus(board_constants_pkg::GpioDirAddr, 32'h0000_00f0);
    expect_byte(gpio_oe, 8'hf0, "GPIO direction write reaches GPIO MMIO");
    set_read_addr(board_constants_pkg::GpioDirAddr);
    expect_word(dbus_read_data, 32'h0000_00f0, "GPIO direction read routes through board bus");

    write_bus(board_constants_pkg::GpioSetAddr, 32'h0000_000a);
    expect_byte(gpio_out, 8'h5f, "GPIO set write routes through board bus");
    write_bus(board_constants_pkg::GpioClearAddr, 32'h0000_0015);
    expect_byte(gpio_out, 8'h4a, "GPIO clear write routes through board bus");
    write_bus(board_constants_pkg::GpioToggleAddr, 32'h0000_00ff);
    expect_byte(gpio_out, 8'hb5, "GPIO toggle write routes through board bus");

    set_read_addr(board_constants_pkg::UartStatusAddr);
    expect_word(dbus_read_data, 32'h0000_0001, "UART status read routes ready bit");
    write_bus(board_constants_pkg::UartTxAddr, 32'h0000_0055);
    set_read_addr(board_constants_pkg::UartStatusAddr);
    expect_word(dbus_read_data, 32'h0000_0000, "UART TX write makes UART busy");
    expect_byte(led, 8'h11, "UART write does not change LED MMIO");

    repeat (2) @(posedge clk);
    set_read_addr(board_constants_pkg::TimerLoAddr);
    if (dbus_read_data == '0) begin
      errors++;
      $display("  FAIL [%0t] timer low read: got zero after reset release", $time);
    end
    checks++;

    set_read_addr(board_constants_pkg::TimerHiAddr);
    expect_word(dbus_read_data, '0, "timer high read routes through board bus");

    set_read_addr(board_constants_pkg::SpiDataAddr);
    expect_word(dbus_read_data, '0, "SPI data read routes through board bus");

    set_read_addr(board_constants_pkg::SpiControlAddr);
    expect_word(dbus_read_data, '0, "SPI control read routes through board bus");

    set_read_addr(board_constants_pkg::SpiStatusAddr);
    expect_word(dbus_read_data, '0, "SPI status read routes through board bus");

    set_read_addr(board_constants_pkg::I2cDataAddr);
    expect_word(dbus_read_data, '0, "I2C data read routes through board bus");

    set_read_addr(board_constants_pkg::I2cAddressAddr);
    expect_word(dbus_read_data, '0, "I2C address read routes through board bus");

    set_read_addr(board_constants_pkg::I2cControlAddr);
    expect_word(dbus_read_data, '0, "I2C control read routes through board bus");

    set_read_addr(board_constants_pkg::I2cStatusAddr);
    expect_word(dbus_read_data, '0, "I2C status read routes through board bus");

    if (errors == 0) begin
      $display("tb_board_bus: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_board_bus: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge clk);
    $display("tb_board_bus: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
