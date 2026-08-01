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
  parameter word_t       SimHaltAddr    = board_constants_pkg::SimHaltAddr,
  parameter int unsigned TimeoutCycles  = 1_000_000
);
  localparam realtime ClkPeriod = 10ns;

  logic         _clk;
  logic         _rst;
  pc_t          _pc;
  pc_t          _imem_addr;
  instr_u       _instr;
  logic   [7:0] _led;
  logic   [7:0] _led_prev;
  logic         _sim_halt_selected;
  logic         _halted;
  logic         _uart_tx;
  logic         _core_imem_en;
  dbus_if _core_dbus ();
  dbus_if _board_dbus ();

  assign _sim_halt_selected = (_core_dbus.addr == SimHaltAddr);
  assign _core_dbus.read_data = _sim_halt_selected ? '0 : _board_dbus.read_data;
  assign _core_dbus.ready = _sim_halt_selected ? _core_dbus.valid : _board_dbus.ready;
  assign _board_dbus.valid = _core_dbus.valid & !_sim_halt_selected;
  assign _board_dbus.write_en = _core_dbus.write_en & !_sim_halt_selected;
  assign _board_dbus.addr = _core_dbus.addr;
  assign _board_dbus.write_data = _core_dbus.write_data;
  assign _board_dbus.size = _core_dbus.size;
  assign _board_dbus.mem_unsigned = _core_dbus.mem_unsigned;

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

  imem #(
    .DepthWords(ImemDepthWords),
    .InitFile(ImemInitFile)
  ) _imem (
    .clk(_clk),
    .rst(_rst),
    .en(_core_imem_en),
    .addr(_imem_addr),
    .instr(_instr.raw)
  );

  core _core (
    .clk(_clk),
    .rst(_rst),
    .instr(_instr),
    .pc(_pc),
    .imem_addr(_imem_addr),
    .halted(_halted),
    .dbus(_core_dbus),
    .imem_en(_core_imem_en)
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
      if (!_rst && _core_dbus.valid && _core_dbus.write_en && _sim_halt_selected) begin
        repeat (ClocksPerBit * 12) @(posedge _clk);
        $write("\n");
        $display("top_sim: halt code 0x%08h _pc=0x%08h", _core_dbus.write_data, _pc);
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
    $fatal(1, "top_sim: watchdog timeout after %0d cycles", TimeoutCycles);
  end

endmodule
