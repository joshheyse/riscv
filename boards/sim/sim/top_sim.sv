`timescale 1ns / 1ps

module top_sim
  import riscv_pkg::*;
#(
  parameter string       ImemInitFile   = "",
  parameter int unsigned ImemDepthWords = 512,
  parameter int unsigned DmemDepthWords = 512,
  parameter string       DmemInitFile   = "",
  parameter int unsigned ClockHz        = board_constants_pkg::ClockHz,
  parameter int unsigned UartBaud       = board_constants_pkg::UartBaud,
  parameter int unsigned ClocksPerBit   = ClockHz / UartBaud,
  parameter mem_addr_t   SimHaltAddr    = board_constants_pkg::SimHaltAddr,
  parameter int unsigned TimeoutCycles  = 1_000_000
);
  localparam realtime ClkPeriod = 10ns;

  logic              _clk;
  logic              _rst;
  pc_t               _pc;
  logic        [7:0] _led;
  logic        [7:0] _led_prev;
  logic              _sim_halt_selected;
  logic              _halted;
  logic              _uart_tx;
  logic              _retire;
  logic              _sim_halt_fire;
  logic              _sim_done;
  int unsigned       _cycle;
  int unsigned       _instret;
  dbus_if _core_dbus ();
  dbus_if _board_dbus ();

  ibus_if _core_ibus ();
  ibus_if _imem_ibus ();

  assign _sim_halt_selected = (_core_dbus.req.addr == SimHaltAddr);
  assign _sim_halt_fire = !_rst && _core_dbus.req.valid && _core_dbus.req.write_en
                          && _sim_halt_selected;

`ifdef CPU_DESIGN_pipelined
  assign _retire = _core._ex_mem.valid && !_core._dbus_wait;
`else
  assign _retire = _core._retire;
`endif

  assign _core_dbus.rsp.read_data = _sim_halt_selected ? '0 : _board_dbus.rsp.read_data;
  assign _core_dbus.rsp.ready = _sim_halt_selected ? _core_dbus.req.valid : _board_dbus.rsp.ready;
  assign _board_dbus.req.valid = _core_dbus.req.valid & !_sim_halt_selected;
  assign _board_dbus.req.write_en = _core_dbus.req.write_en & !_sim_halt_selected;
  assign _board_dbus.req.addr = _core_dbus.req.addr;
  assign _board_dbus.req.write_data = _core_dbus.req.write_data;
  assign _board_dbus.req.write_mask = _core_dbus.req.write_mask;

  assign _core_ibus.rsp = _imem_ibus.rsp;
  assign _imem_ibus.req = _core_ibus.req;

  initial begin
    if (ImemInitFile == "") begin
      $fatal(1, "top_sim needs -GImemInitFile=<program.mem>");
    end
  end

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  initial begin
    _rst = 1'b1;
    repeat (4) @(posedge _clk);
    _rst = 1'b0;
  end

  always_ff @(posedge _clk) begin
    if (_rst) begin
      _cycle <= 0;
      _instret <= 0;
      _sim_done <= 1'b0;
    end else if (!_sim_done) begin
      _cycle <= _cycle + 1;
      if (_retire) begin
        _instret <= _instret + 1;
      end
      if (_sim_halt_fire) begin
        _sim_done <= 1'b1;
      end
    end
  end

  imem #(
    .DepthWords(ImemDepthWords),
    .InitFile(ImemInitFile)
  ) _imem (
    .clk(_clk),
    .rst(_rst),
    .ibus(_imem_ibus)
  );

  core _core (
    .clk(_clk),
    .rst(_rst),
    .pc(_pc),
    .halted(_halted),
    .dbus(_core_dbus),
    .ibus(_core_ibus)
  );

  board_bus #(
    .DmemDepthWords(DmemDepthWords),
    .DmemInitFile(DmemInitFile)
  ) _board_bus (
    .clk(_clk),
    .rst(_rst),
    .led(_led),
    .uart_tx(_uart_tx),
    .dbus(_board_dbus)
  );

  task automatic uart_getc(output byte ch);
    @(negedge _uart_tx);
    #(ClkPeriod * ClocksPerBit / 2);

    if (_uart_tx !== 1'b0) begin
      $error("UART start bit was not stable low");
    end

    #(ClkPeriod * ClocksPerBit);
    for (int i = 0; i < 8; i++) begin
      ch[i] = _uart_tx;
      #(ClkPeriod * ClocksPerBit);
    end

    if (_uart_tx !== 1'b1) begin
      $error("UART stop bit was not high after byte 0x%02h", ch);
    end
  endtask

  initial begin
    byte ch;

    $display("top_sim: IMEM %s", ImemInitFile);
    $write("uart: ");

    forever begin
      uart_getc(ch);
      $write("%c", ch);
      if ($test$plusargs("uart-bytes")) begin
        $display("top_sim: uart byte 0x%02h", ch);
      end
    end
  end

  always_ff @(posedge _clk) begin
    if (_rst) begin
      _led_prev <= '0;
    end else if (_led != _led_prev) begin
      $display("_led: 0x%02h", _led);
      _led_prev <= _led;
    end
  end

  initial begin
    forever begin
      @(posedge _clk);
      if (_sim_halt_fire) begin
        repeat (ClocksPerBit * 12) @(posedge _clk);
        $write("\n");
        $display("top_sim: halt code 0x%08h _pc=0x%08h", _core_dbus.req.write_data, _pc);
        $display("top_sim: stats cycles=%0d instret=%0d", _cycle, _instret);
        $finish;
      end
    end
  end

  always_ff @(posedge _clk) begin
    if (!_rst && _halted) begin
      $fatal(1, "top_sim: core _halted before firmware wrote SIM_HALT");
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display(
        "top_sim: watchdog state cycle=%0d _pc=0x%08h halted=%b ibus_valid=%b ibus_addr=0x%08h ibus_ready=%b dbus_valid=%b dbus_write_en=%b dbus_addr=0x%08h dbus_write_data=0x%08h dbus_ready=%b",
        _cycle, _pc, _halted, _core_ibus.req.valid, _core_ibus.req.addr, _core_ibus.rsp.ready,
        _core_dbus.req.valid, _core_dbus.req.write_en, _core_dbus.req.addr,
        _core_dbus.req.write_data, _core_dbus.rsp.ready);
    $fatal(1, "top_sim: watchdog timeout after %0d cycles", TimeoutCycles);
  end

endmodule
