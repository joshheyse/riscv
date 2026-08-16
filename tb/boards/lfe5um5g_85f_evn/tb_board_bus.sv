`timescale 1ns / 1ps

module tb_board_bus
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned PushButtonDebounceCycles = 120_000;
  localparam int unsigned TimeoutCycles = PushButtonDebounceCycles + 1_000;

  logic                                    _clk;
  logic                                    _rst;
  logic [                             7:0] _led;
  logic [                             7:0] _dip_switch;
  logic                                    _push_button;
  logic [board_constants_pkg::NumGpio-1:0] _gpio_in;
  logic [board_constants_pkg::NumGpio-1:0] _gpio_out;
  logic [board_constants_pkg::NumGpio-1:0] _gpio_oe;
  mem_if dbus ();
  irq_if _irq ();
  uart_if _uart ();
  spi_if _spi ();
  i2c_if _i2c ();

  int unsigned errors = 0;
  int unsigned checks = 0;

  board_bus #(
    .MemDepthWords(16)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .led(_led),
    .dip_switch(_dip_switch),
    .push_button(_push_button),
    .uart(_uart),
    .spi(_spi),
    .i2c(_i2c),
    .gpio_in(_gpio_in),
    .gpio_out(_gpio_out),
    .gpio_oe(_gpio_oe),
    .mem(dbus),
    .irq(_irq)
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
    @(negedge _clk);
    dbus.req.valid = 1'b1;
    dbus.req.write_en = 1'b0;
    dbus.req.addr = addr;
    @(posedge _clk);
    #1;
    expect_bit(dbus.rsp.ready, 1'b1, "read ready");
    dbus.req.valid = 1'b0;
  endtask

  task automatic write_bus(input word_t addr, input word_t data);
    @(negedge _clk);
    dbus.req.valid      = 1'b1;
    dbus.req.addr       = addr;
    dbus.req.write_data = data;
    dbus.req.write_mask = 4'b1111;
    dbus.req.write_en   = 1'b1;
    @(posedge _clk);
    #1;
    expect_bit(dbus.rsp.ready, 1'b1, "write ready");
    dbus.req.valid = 1'b0;
    dbus.req.write_en = 1'b0;
  endtask

  task automatic claim_irq(input word_t exp_id, input string what);
    @(negedge _clk);
    dbus.req.valid      = 1'b1;
    dbus.req.write_en   = 1'b0;
    dbus.req.addr       = board_constants_pkg::PlicMClaimCompleteAddr;
    dbus.req.write_data = '0;
    dbus.req.write_mask = 4'b1111;
    #1;
    expect_bit(dbus.rsp.ready, 1'b1, {what, " ready"});
    expect_word(dbus.rsp.read_data, exp_id, what);
    @(posedge _clk);
    #1;
    dbus.req.valid = 1'b0;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_board_bus);
    end

    _rst                = 1'b1;
    dbus.req.valid      = 1'b0;
    dbus.req.write_en   = 1'b0;
    dbus.req.addr       = '0;
    dbus.req.write_data = '0;
    dbus.req.write_mask = '0;
    _dip_switch         = 8'h00;
    _push_button        = 1'b0;
    _spi.miso           = 1'b0;
    _i2c.sda_in         = 1'b1;
    _i2c.scl_in         = 1'b1;
    _gpio_in            = '0;
    _uart.rx            = 1'b1;

    repeat (2) @(posedge _clk);
    #1;
    expect_byte(_led, 8'h00, "reset clears LEDs");
    expect_byte(_gpio_out, 8'h00, "reset clears GPIO output latch");
    expect_byte(_gpio_oe, 8'h00, "reset clears GPIO output enable");
    expect_bit(_uart.tx, 1'b1, "reset leaves UART idle high");
    expect_bit(_spi.sck, 1'b0, "reset leaves SPI clock idle low");
    expect_bit(_spi.mosi, 1'b0, "reset leaves SPI MOSI idle low");
    expect_bit(_spi.cs_n, 1'b1, "reset leaves SPI chip select inactive");
    expect_bit(_i2c.sda_drive_low, 1'b0, "reset releases I2C SDA");
    expect_bit(_i2c.scl_drive_low, 1'b0, "reset releases I2C SCL");

    @(negedge _clk);
    _rst = 1'b0;

    set_read_addr(32'h2000_0000);
    expect_word(dbus.rsp.read_data, '0, "unmapped read returns zero");

    write_bus(board_constants_pkg::LedAddr, 32'h0000_00a5);
    expect_byte(_led, 8'ha5, "LED write reaches LED MMIO");
    set_read_addr(board_constants_pkg::LedAddr);
    expect_word(dbus.rsp.read_data, 32'h0000_00a5, "LED read routes through board bus");

    write_bus(32'h2000_0000, 32'h0000_005a);
    expect_byte(_led, 8'ha5, "unmapped write does not change LED MMIO");
    set_read_addr(32'h2000_0000);
    expect_word(dbus.rsp.read_data, '0, "unmapped read still returns zero after write");

    write_bus(board_constants_pkg::MemBase + 32'h0000_0004, 32'hdead_beef);
    set_read_addr(board_constants_pkg::MemBase + 32'h0000_0004);
    expect_word(dbus.rsp.read_data, 32'hdead_beef, "memory write/read routes to LSU");

    write_bus(board_constants_pkg::LedAddr, 32'h0000_0011);
    set_read_addr(board_constants_pkg::MemBase + 32'h0000_0004);
    expect_word(dbus.rsp.read_data, 32'hdead_beef, "LED write does not change memory");

    write_bus(board_constants_pkg::PlicPriorityBaseAddr + (4 * board_constants_pkg::PlicIrqUart),
              32'd1);
    write_bus(
        board_constants_pkg::PlicPriorityBaseAddr + (4 * board_constants_pkg::PlicIrqDipSwitch),
        32'd2);
    write_bus(
        board_constants_pkg::PlicPriorityBaseAddr + (4 * board_constants_pkg::PlicIrqPushButton),
        32'd3);
    write_bus(board_constants_pkg::PlicMEnableAddr, 32'h0000_000e);
    write_bus(board_constants_pkg::PlicMThresholdAddr, 32'd0);
    set_read_addr(board_constants_pkg::PlicMEnableAddr);
    expect_word(dbus.rsp.read_data, 32'h0000_000e, "PLIC enable routes through board bus");

    _dip_switch = 8'hc3;
    repeat (3) @(posedge _clk);
    #1;
    set_read_addr(board_constants_pkg::DipSwitchAddr);
    expect_word(dbus.rsp.read_data, 32'h0000_00c3, "DIP switch read routes through board bus");
    expect_bit(_irq.pending.meip, 1'b0, "disabled DIP switch event does not raise meip");
    set_read_addr(board_constants_pkg::DipSwitchIrqPendingAddr);
    expect_word(dbus.rsp.read_data, 32'h0000_00c3, "DIP switch pending routes through board bus");
    write_bus(board_constants_pkg::DipSwitchIrqEnableAddr, 32'h0000_00ff);
    @(posedge _clk);
    #1;
    expect_bit(_irq.pending.meip, 1'b1, "enabled DIP switch event reaches board IRQ");
    claim_irq(board_constants_pkg::PlicIrqDipSwitch, "claim DIP switch PLIC source");
    expect_bit(_irq.pending.meip, 1'b0, "claim removes DIP switch source from arbitration");
    write_bus(board_constants_pkg::DipSwitchIrqPendingAddr, 32'h0000_00c3);
    write_bus(board_constants_pkg::PlicMClaimCompleteAddr, board_constants_pkg::PlicIrqDipSwitch);
    expect_bit(_irq.pending.meip, 1'b0, "cleared and completed DIP switch stays idle");

    _push_button = 1'b1;
    repeat (PushButtonDebounceCycles + 3) @(posedge _clk);
    #1;
    set_read_addr(board_constants_pkg::PushButtonAddr);
    expect_word(dbus.rsp.read_data, 32'h0000_0001, "push button read routes through board bus");
    expect_bit(_irq.pending.meip, 1'b0, "disabled push-button event does not raise meip");
    set_read_addr(board_constants_pkg::PushButtonIrqPendingAddr);
    expect_word(dbus.rsp.read_data, 32'h0000_0001, "push-button pending routes through board bus");
    write_bus(board_constants_pkg::PushButtonIrqEnableAddr, 32'h0000_0001);
    @(posedge _clk);
    #1;
    expect_bit(_irq.pending.meip, 1'b1, "enabled push-button event reaches board IRQ");
    claim_irq(board_constants_pkg::PlicIrqPushButton, "claim push-button PLIC source");
    expect_bit(_irq.pending.meip, 1'b0, "claim removes push-button source from arbitration");
    write_bus(board_constants_pkg::PushButtonIrqPendingAddr, 32'h0000_0001);
    write_bus(board_constants_pkg::PlicMClaimCompleteAddr, board_constants_pkg::PlicIrqPushButton);
    expect_bit(_irq.pending.meip, 1'b0, "cleared and completed push button stays idle");

    _gpio_in = 8'h3c;
    set_read_addr(board_constants_pkg::GpioDataInAddr);
    expect_word(dbus.rsp.read_data, 32'h0000_003c, "GPIO input read routes through board bus");

    write_bus(board_constants_pkg::GpioDataOutAddr, 32'h0000_0055);
    expect_byte(_gpio_out, 8'h55, "GPIO output write reaches GPIO MMIO");
    set_read_addr(board_constants_pkg::GpioDataOutAddr);
    expect_word(dbus.rsp.read_data, 32'h0000_0055, "GPIO output read routes through board bus");

    write_bus(board_constants_pkg::GpioDirAddr, 32'h0000_00f0);
    expect_byte(_gpio_oe, 8'hf0, "GPIO direction write reaches GPIO MMIO");
    set_read_addr(board_constants_pkg::GpioDirAddr);
    expect_word(dbus.rsp.read_data, 32'h0000_00f0, "GPIO direction read routes through board bus");

    write_bus(board_constants_pkg::GpioSetAddr, 32'h0000_000a);
    expect_byte(_gpio_out, 8'h5f, "GPIO set write routes through board bus");
    write_bus(board_constants_pkg::GpioClearAddr, 32'h0000_0015);
    expect_byte(_gpio_out, 8'h4a, "GPIO clear write routes through board bus");
    write_bus(board_constants_pkg::GpioToggleAddr, 32'h0000_00ff);
    expect_byte(_gpio_out, 8'hb5, "GPIO toggle write routes through board bus");

    set_read_addr(board_constants_pkg::UartStatusAddr);
    expect_word(dbus.rsp.read_data, 32'h0000_0001, "UART status read routes ready bit");
    write_bus(board_constants_pkg::UartTxAddr, 32'h0000_0055);
    set_read_addr(board_constants_pkg::UartStatusAddr);
    expect_word(dbus.rsp.read_data, 32'h0000_0000, "UART TX write makes UART busy");
    expect_byte(_led, 8'h11, "UART write does not change LED MMIO");

    repeat (2) @(posedge _clk);
    set_read_addr(board_constants_pkg::TimerLoAddr);
    if (dbus.rsp.read_data == '0) begin
      errors++;
      $display("  FAIL [%0t] timer low read: got zero after reset release", $time);
    end
    checks++;

    set_read_addr(board_constants_pkg::TimerHiAddr);
    expect_word(dbus.rsp.read_data, '0, "timer high read routes through board bus");

    set_read_addr(board_constants_pkg::SpiDataAddr);
    expect_word(dbus.rsp.read_data, '0, "SPI data read routes through board bus");

    set_read_addr(board_constants_pkg::SpiControlAddr);
    expect_word(dbus.rsp.read_data, '0, "SPI control read routes through board bus");

    set_read_addr(board_constants_pkg::SpiStatusAddr);
    expect_word(dbus.rsp.read_data, '0, "SPI status read routes through board bus");

    set_read_addr(board_constants_pkg::I2cDataAddr);
    expect_word(dbus.rsp.read_data, '0, "I2C data read routes through board bus");

    set_read_addr(board_constants_pkg::I2cAddressAddr);
    expect_word(dbus.rsp.read_data, '0, "I2C address read routes through board bus");

    set_read_addr(board_constants_pkg::I2cControlAddr);
    expect_word(dbus.rsp.read_data, '0, "I2C control read routes through board bus");

    set_read_addr(board_constants_pkg::I2cStatusAddr);
    expect_word(dbus.rsp.read_data, '0, "I2C status read routes through board bus");

    if (errors == 0) begin
      $display("tb_board_bus: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_board_bus: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_board_bus: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
