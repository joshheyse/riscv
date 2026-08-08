`timescale 1ns / 1ps

module tb_uart_mmio
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 1_000;
  localparam int unsigned ClocksPerBit = 4;
  localparam word_t TxDataAddr = 32'h1000_1000;
  localparam word_t RxDataAddr = 32'h1000_1004;
  localparam word_t MsipAddr   = 32'h1000_1008;
  localparam word_t StatusAddr = 32'h1000_4000;

  logic            _clk;
  logic            _rst;
  logic            _mem_valid;
  logic            _mem_write_en;
  word_t           _mem_addr;
  word_t           _mem_write_data;
  mem_write_mask_t _mem_write_mask;
  logic            _selected;
  word_t           _read_data;
  uart_if          _uart ();
  mem_if _mem ();
  irq_if           _irq ();

  int unsigned errors = 0;
  int unsigned checks = 0;

  assign _mem.req.valid = _mem_valid;
  assign _mem.req.write_en = _mem_write_en;
  assign _mem.req.addr = _mem_addr;
  assign _mem.req.write_data = _mem_write_data;
  assign _mem.req.write_mask = _mem_write_mask;
  assign _read_data = _mem.rsp.read_data;

  uart_mmio #(
    .ClocksPerBit(ClocksPerBit),
    .TxDataAddr(TxDataAddr),
    .RxDataAddr(RxDataAddr),
    .MsipAddr(MsipAddr),
    .StatusAddr(StatusAddr)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .mem(_mem),
    .selected(_selected),
    .uart(_uart),
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

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic write_mmio(input word_t a, input word_t data);
    @(negedge _clk);
    _mem_addr       = a;
    _mem_write_data = data;
    _mem_write_mask = 4'b1111;
    _mem_valid      = 1'b1;
    _mem_write_en   = 1'b1;
    @(posedge _clk);
    #1;
    _mem_write_en = 1'b0;
  endtask

  task automatic expect_status(input logic ready, input logic overrun, input logic tx_ready, input string what);
    word_t       _read;

    @(negedge _clk);
    _mem_addr = StatusAddr;
    _mem_valid = 1'b1;
    _mem_write_en = 1'b0;
    #1;
    expect_bit(_selected, 1'b1, "status address selected");
    read_mmio(StatusAddr, _read);
    expect_word(_read, {29'b0, overrun, ready, tx_ready}, what);
  endtask

  task automatic expect_status_ready(input logic ready, input string what);
    expect_status(ready, 1'b0, 1'b1, what);
  endtask

  task automatic expect_tx_bit(input logic exp, input string what);
    repeat (ClocksPerBit / 2) @(posedge _clk);
    #1;
    expect_bit(_uart.tx, exp, what);
    repeat (ClocksPerBit - (ClocksPerBit / 2)) @(posedge _clk);
  endtask

  task automatic read_mmio(input word_t a, output word_t data);
    @(negedge _clk);
    _mem_addr     = a;
    _mem_write_en = 1'b0;
    _mem_valid    = 1'b1;
    @(posedge _clk);
    #1;
    data = _read_data;
    _mem_valid = 1'b0;
  endtask

  task automatic read_status(
    output logic rx_ready,
    output logic rx_overrun,
    output logic tx_ready
  );
    logic [2:0] _status;
    /* verilator lint_off UNUSEDSIGNAL */
    word_t      _full_status;
    /* verilator lint_on UNUSEDSIGNAL */

    read_mmio(StatusAddr, _full_status);
    _status = _full_status[2:0];
    rx_ready   = _status[1];
    rx_overrun = _status[2];
    tx_ready   = _status[0];
  endtask

  task automatic wait_for_rx_ready();
    int i;
    /* verilator lint_off UNUSEDSIGNAL */
    word_t _status_word;
    /* verilator lint_on UNUSEDSIGNAL */
    logic _status_ready;

    for (i = 0; i < (ClocksPerBit * 20); i++) begin
      read_mmio(StatusAddr, _status_word);
      _status_ready = _status_word[1];
      if (_status_ready) begin
        return;
      end
      @(negedge _clk);
    end

    expect_bit(1'b1, 1'b1, "rx ready timeout");
  endtask

  task automatic send_uart_byte(input byte_t data);
    int i;
    @(negedge _clk);
      _uart.rx = 1'b0;

    wait (_dut._state == UART_RX_DATA);

    for (i = 0; i < 8; i++) begin
      @(negedge _clk);
      _uart.rx = data[i];
      do begin
        @(posedge _clk);
      end while (!_dut._rx_stg_tick);
    end

    @(negedge _clk);
      _uart.rx = 1'b1;
    do begin
      @(posedge _clk);
    end while (_dut._state != UART_RX_IDLE);
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_uart_mmio);
    end

`ifdef UART_DEBUG
    fork
      forever begin
        @(posedge _clk);
        $display("t=%0t tx=%b busy=%b idx=%0d data=%h data_bit_idx=%0d state=%0d rx=%b",
          $time,
          _uart.tx,
          _dut._tx_busy,
          _dut._tx_bit_idx,
          _dut._tx_data,
          _dut._tx_data_bit_idx,
          _dut._state,
          _uart.rx);
      end
    join_none
`endif

    _rst            = 1'b1;
    _mem_valid      = 1'b0;
    _mem_write_en   = 1'b0;
    _mem_addr       = '0;
    _mem_write_data = '0;
    _mem_write_mask = '0;
    _uart.rx        = 1'b1;

    repeat (2) @(posedge _clk);
    #1;
    expect_bit(_uart.tx, 1'b1, "reset drives UART idle high");

    @(negedge _clk);
    _rst = 1'b0;
    expect_status(1'b0, 1'b0, 1'b1, "idle status ready");

    write_mmio(TxDataAddr, 32'h0000_00a5);

    // 0xa5 = 8'b1010_0101, transmitted LSB first:
    // start, 1, 0, 1, 0, 0, 1, 0, 1, stop.
    expect_tx_bit(1'b0, "start bit");
    expect_tx_bit(1'b1, "data bit 0");
    expect_tx_bit(1'b0, "data bit 1");
    expect_tx_bit(1'b1, "data bit 2");
    expect_tx_bit(1'b0, "data bit 3");
    expect_tx_bit(1'b0, "data bit 4");
    expect_tx_bit(1'b1, "data bit 5");
    expect_tx_bit(1'b0, "data bit 6");
    expect_tx_bit(1'b1, "data bit 7");
    expect_tx_bit(1'b1, "stop bit");

    repeat (1) @(posedge _clk);
    expect_status(1'b0, 1'b0, 1'b1, "ready after stop bit");
    expect_bit(_uart.tx, 1'b1, "idle high after frame");

    @(negedge _clk);
    _mem_addr     = TxDataAddr;
    _mem_valid    = 1'b1;
    _mem_write_en = 1'b0;
    #1;
    expect_bit(_selected, 1'b1, "tx data address selected");
    expect_word(_read_data, 32'h0000_0000, "non-status read_data is zero");
    _mem_valid = 1'b0;
    expect_bit(_irq.pending.msip, 1'b0, "reset clears msip");
    expect_bit(_irq.pending.meip, 1'b0, "reset clears meip");

    expect_bit(_dut._tx_busy, 1'b0, "tx is not busy after frame");

    read_mmio(StatusAddr, _mem_write_data);
    expect_word(_mem_write_data, 32'h0000_0001, "status after frame complete");

    write_mmio(MsipAddr, 32'h0000_0001);
    read_mmio(MsipAddr, _mem_write_data);
    expect_word(_mem_write_data, 32'h0000_0001, "msip write/readback");
    expect_bit(_irq.pending.msip, 1'b1, "msip write sets pending msip output");

    write_mmio(MsipAddr, 32'h0000_0000);
    read_mmio(MsipAddr, _mem_write_data);
    expect_word(_mem_write_data, 32'h0000_0000, "msip clear write/readback");
    expect_bit(_irq.pending.msip, 1'b0, "msip clear clears pending msip output");

    @(negedge _clk);
    _mem_addr = 32'h2000_0000;
    #1;
    expect_bit(_selected, 1'b0, "unmapped address not selected");

    write_mmio(TxDataAddr, 32'h0000_003c);
    expect_tx_bit(1'b0, "second frame start");

    @(negedge _clk);
    _mem_addr       = TxDataAddr;
    _mem_write_data = 32'h0000_00ff;
    _mem_write_en   = 1'b1;
    @(posedge _clk);
    #1;
    _mem_write_en = 1'b0;

    expect_tx_bit(1'b0, "second frame data bit 0 ignores busy write");
    expect_tx_bit(1'b0, "second frame data bit 1 ignores busy write");
    expect_tx_bit(1'b1, "second frame data bit 2 ignores busy write");

    // ---------------------------------------------------------------- RX behavior --
    // RX receive should set rx-ready exactly when frame completes and clear only on
    // explicit read of RxDataAddr.
    send_uart_byte(8'h5A);
    wait_for_rx_ready();
    expect_status(1'b1, 1'b0, 1'b1, "rx-ready set after byte receive");
    expect_bit(_irq.pending.meip, 1'b1, "meip set when rx data ready");

    read_mmio(RxDataAddr, _mem_write_data);
    expect_word(_mem_write_data, 32'h0000_005a, "rx-data read after first frame");
    expect_status(1'b0, 1'b0, 1'b1, "rx-ready clears after data read");
    expect_bit(_irq.pending.meip, 1'b0, "meip clears when rx data consumed");

    // Overrun should set when a new byte arrives before data is consumed.
    send_uart_byte(8'h3C);
    send_uart_byte(8'hA5);
    wait_for_rx_ready();
    @(negedge _clk);
    read_mmio(StatusAddr, _mem_write_data);
    expect_word(_mem_write_data, {29'b0, 1'b1, 1'b1, 1'b1}, "status after overrun");

    read_mmio(RxDataAddr, _mem_write_data);
    expect_word(_mem_write_data, 32'h0000_00a5, "rx-data after overrun keeps latest frame");

    if (errors == 0) begin
      $display("tb_uart_mmio: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_uart_mmio: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_uart_mmio: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
