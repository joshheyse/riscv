`timescale 1ns / 1ps

module top_sim
  import riscv_pkg::*;
#(
  parameter string       MemInitFile    = "",
  parameter int unsigned MemDepthWords  = 1024,
  parameter int unsigned ClockHz        = board_constants_pkg::ClockHz,
  parameter int unsigned UartBaud       = board_constants_pkg::UartBaud,
  parameter int unsigned ClocksPerBit   = ClockHz / UartBaud,
  parameter mem_addr_t   SimHaltAddr    = board_constants_pkg::SimHaltAddr,
  parameter mem_addr_t   CacheableBase  = board_constants_pkg::MemBase,
  parameter mem_addr_t   CacheableEnd   = board_constants_pkg::MemBase + board_constants_pkg::MemSize,
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
  logic              _uart_rx;
  logic              _retire;
  logic              _sim_halt_fire;
  logic              _sim_done;
  mem_data_t         _sim_halt_code;
  int unsigned       _cycle;
  int unsigned       _instret;
  logic              _plic_claim_seen;
  logic              _plic_complete_seen;
  logic              _plic_mret_seen;
  logic              _plic_uart_tx_seen;
  mem_if _core_mem ();
  mem_if _board_mem ();
  irq_if _irq ();
  uart_if _uart ();

  assign _sim_halt_selected = (_core_mem.req.addr == SimHaltAddr);
  assign _sim_halt_fire = !_rst && _core_mem.req.valid && _core_mem.req.write_en
                          && _sim_halt_selected;

  assign _retire = _core._ex_mem.valid && !_core._dbus_wait;

  assign _core_mem.rsp.read_data = _sim_halt_selected ? '0 : _board_mem.rsp.read_data;
  assign _core_mem.rsp.ready = _sim_halt_selected ? _core_mem.req.valid : _board_mem.rsp.ready;
  assign _board_mem.req.valid = _core_mem.req.valid & !_sim_halt_selected;
  assign _board_mem.req.write_en = _core_mem.req.write_en & !_sim_halt_selected;
  assign _board_mem.req.addr = _core_mem.req.addr;
  assign _board_mem.req.write_data = _core_mem.req.write_data;
  assign _board_mem.req.write_mask = _core_mem.req.write_mask;
  assign _uart.rx = _uart_rx;

  initial begin
    if (MemInitFile == "") begin
      $fatal(1, "top_sim needs -GMemInitFile=<program.mem>");
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
      _sim_halt_code <= '0;
      _plic_claim_seen <= 1'b0;
      _plic_complete_seen <= 1'b0;
      _plic_mret_seen <= 1'b0;
      _plic_uart_tx_seen <= 1'b0;
    end else if (!_sim_done) begin
      _cycle <= _cycle + 1;
      if (_retire) begin
        _instret <= _instret + 1;
      end
      if (_sim_halt_fire) begin
        _sim_done <= 1'b1;
        _sim_halt_code <= _core_mem.req.write_data;
      end

      if ($test$plusargs("plic-checkpoints")) begin
        if (_core_mem.req.valid && _core_mem.rsp.ready && !_core_mem.req.write_en &&
            (_core_mem.req.addr == board_constants_pkg::PlicMClaimCompleteAddr)) begin
          _plic_claim_seen <= 1'b1;
          $display("top_sim: checkpoint plic claim id=0x%08h", _core_mem.rsp.read_data);
        end
        if (_core_mem.req.valid && _core_mem.rsp.ready && _core_mem.req.write_en &&
            (_core_mem.req.addr == board_constants_pkg::PlicMClaimCompleteAddr)) begin
          _plic_complete_seen <= 1'b1;
          $display("top_sim: checkpoint plic complete id=0x%08h", _core_mem.req.write_data);
        end
        if (_core_mem.req.valid && _core_mem.rsp.ready && _core_mem.req.write_en &&
            (_core_mem.req.addr == board_constants_pkg::UartTxAddr)) begin
          _plic_uart_tx_seen <= 1'b1;
          $display("top_sim: checkpoint uart tx accepted byte=0x%02h",
                   _core_mem.req.write_data[7:0]);
        end
        if (_core._retire.mret) begin
          _plic_mret_seen <= 1'b1;
          $display("top_sim: checkpoint mret retired");
        end
      end
    end
  end

  core #(
    .CacheableBase(CacheableBase),
    .CacheableEnd (CacheableEnd)
  ) _core (
    .clk(_clk),
    .rst(_rst),
    .pc(_pc),
    .halted(_halted),
    .mem(_core_mem),
    .irq(_irq)
  );

  board_bus #(
    .MemDepthWords(MemDepthWords),
    .MemInitFile(MemInitFile)
  ) _board_bus (
    .clk(_clk),
    .rst(_rst),
    .led(_led),
    .uart(_uart),
    .irq(_irq),
    .mem(_board_mem)
  );

  task automatic uart_getc(output byte ch);
    @(negedge _uart.tx);
    #(ClkPeriod * ClocksPerBit / 2);

    if (_uart.tx !== 1'b0) begin
      $error("UART start bit was not stable low");
    end

    #(ClkPeriod * ClocksPerBit);
    for (int i = 0; i < 8; i++) begin
      ch[i] = _uart.tx;
      #(ClkPeriod * ClocksPerBit);
    end

    if (_uart.tx !== 1'b1) begin
      $error("UART stop bit was not high after byte 0x%02h", ch);
    end
  endtask

  task automatic uart_send_byte(input byte ch);
    int unsigned i;

    @(negedge _clk);
    _uart_rx = 1'b0;
    repeat (ClocksPerBit) @(negedge _clk);

    for (i = 0; i < 8; i++) begin
      _uart_rx = ch[i];
      repeat (ClocksPerBit) @(negedge _clk);
    end

    _uart_rx = 1'b1;
    repeat (ClocksPerBit) @(negedge _clk);
  endtask

  task automatic uart_send_string(input string text);
    int unsigned i;
    for (i = 0; i < text.len(); i++) begin
      uart_send_byte(text[i]);
    end
  endtask

  task automatic uart_send_file(input string path);
    integer file;
    integer ch;

    file = $fopen(path, "r");
    if (file == 0) begin
      $display("top_sim: could not open uart_rx_file=%s", path);
      return;
    end

    while (1) begin
      ch = $fgetc(file);
      if (ch < 0) begin
        break;
      end
      uart_send_byte(ch[7:0]);
    end

    $fclose(file);
  endtask

  initial begin
    byte   ch;
    string uart_rx_data;
    string uart_rx_file;

    _uart_rx = 1'b1;

    $display("top_sim: MEM %s", MemInitFile);
    $write("uart: ");

    @(negedge _rst);

    if ($value$plusargs("uart_rx=%s", uart_rx_data)) begin
      uart_send_string(uart_rx_data);
    end

    if ($value$plusargs("uart_rx_file=%s", uart_rx_file)) begin
      uart_send_file(uart_rx_file);
    end

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
        if ($test$plusargs("plic-checkpoints")) begin
          assert (_plic_claim_seen)
          else $fatal(1, "top_sim: missing PLIC claim checkpoint");
          assert (_plic_complete_seen)
          else $fatal(1, "top_sim: missing PLIC completion checkpoint");
          assert (_plic_mret_seen)
          else $fatal(1, "top_sim: missing mret retirement checkpoint");
          assert (_plic_uart_tx_seen)
          else $fatal(1, "top_sim: missing accepted UART TX checkpoint");
          $display("top_sim: checkpoint simulation halt code=0x%08h", _core_mem.req.write_data);
        end
        repeat (ClocksPerBit * 12) @(posedge _clk);
        $write("\n");
        $display("top_sim: halt code 0x%08h _pc=0x%08h", _sim_halt_code, _pc);
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
        "top_sim: watchdog state cycle=%0d _pc=0x%08h halted=%b mem_valid=%b mem_write_en=%b mem_addr=0x%08h mem_write_data=0x%08h mem_ready=%b",
        _cycle, _pc, _halted, _core_mem.req.valid, _core_mem.req.write_en,
        _core_mem.req.addr, _core_mem.req.write_data, _core_mem.rsp.ready);
    $display(
        "top_sim: pipeline ifu_request_valid=%b ifu_request_pc=0x%08h ifu_drop_response=%b fetched_valid=%b if_id_valid=%b id_ex_valid=%b ex_mem_valid=%b mem_wb_valid=%b fetch_ctrl=%0d data_stall=%b dbus_wait=%b flow_action=%0d",
        _core._ifu._request_valid, _core._ifu._request_pc, _core._ifu._drop_response,
        _core._fetched.valid, _core._if_id.valid, _core._id_ex.valid, _core._ex_mem.valid,
        _core._mem_wb.valid, _core._pipe_ctrl.fetch, _core._data_stall, _core._dbus_wait,
        _core._flow.action);
    $fatal(1, "top_sim: watchdog timeout after %0d cycles", TimeoutCycles);
  end

endmodule
