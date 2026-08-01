`timescale 1ns / 1ps

module top_sim
  import riscv_pkg::*;
#(
  parameter string ImemInitFile = "",
  parameter int unsigned ImemDepthWords = 512,
  parameter int unsigned DmemDepthWords = 512,
  parameter string DmemInitFile = "",
  parameter int unsigned ClockHz = board_constants_pkg::ClockHz,
  parameter int unsigned UartBaud = board_constants_pkg::UartBaud,
  parameter int unsigned ClocksPerBit = ClockHz / UartBaud,
  parameter word_t SimHaltAddr = board_constants_pkg::SimHaltAddr,
  parameter int unsigned TimeoutCycles = 1_000_000
);
  localparam realtime ClkPeriod = 10ns;

  logic clk;
  logic rst;
  pc_t pc;
  pc_t imem_addr;
  instr_u instr;
  logic [7:0] led;
  logic [7:0] led_prev;
  logic sim_halt_selected;
  logic halted;
  logic uart_tx;
  logic core_imem_en;
  dbus_if core_dbus ();
  dbus_if board_dbus ();

  assign sim_halt_selected = (core_dbus.addr == SimHaltAddr);
  assign core_dbus.read_data = sim_halt_selected ? '0 : board_dbus.read_data;
  assign core_dbus.ready = sim_halt_selected ? core_dbus.valid : board_dbus.ready;
  assign board_dbus.valid = core_dbus.valid & !sim_halt_selected;
  assign board_dbus.write_en = core_dbus.write_en & !sim_halt_selected;
  assign board_dbus.addr = core_dbus.addr;
  assign board_dbus.write_data = core_dbus.write_data;
  assign board_dbus.size = core_dbus.size;
  assign board_dbus.mem_unsigned = core_dbus.mem_unsigned;

  initial begin
    if (ImemInitFile == "") begin
      $fatal(1, "top_sim needs -GImemInitFile=<program.mem>");
    end
  end

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  initial begin
    rst = 1'b1;
    repeat (4) @(posedge clk);
    rst = 1'b0;
  end

  imem #(
    .DepthWords(ImemDepthWords),
    .InitFile  (ImemInitFile)
  ) imem_i (
    .clk(clk),
    .rst(rst),
    .en(core_imem_en),
    .addr(imem_addr),
    .instr(instr.raw)
  );

  core core_i (
    .clk(clk),
    .rst(rst),
    .instr(instr),
    .pc(pc),
    .imem_addr(imem_addr),
    .halted(halted),
    .dbus(core_dbus),
    .imem_en(core_imem_en)
  );

  board_bus #(
    .DmemDepthWords(DmemDepthWords),
    .DmemInitFile  (DmemInitFile)
  ) board_bus_i (
    .clk(clk),
    .rst(rst),
    .led(led),
    .uart_tx(uart_tx),
    .dbus(board_dbus)
  );

  task automatic uart_getc(output byte ch);
    @(negedge uart_tx);
    #(ClkPeriod * ClocksPerBit / 2);

    if (uart_tx !== 1'b0) begin
      $error("UART start bit was not stable low");
    end

    #(ClkPeriod * ClocksPerBit);
    for (int i = 0; i < 8; i++) begin
      ch[i] = uart_tx;
      #(ClkPeriod * ClocksPerBit);
    end

    if (uart_tx !== 1'b1) begin
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

  always_ff @(posedge clk) begin
    if (rst) begin
      led_prev <= '0;
    end else if (led != led_prev) begin
      $display("led: 0x%02h", led);
      led_prev <= led;
    end
  end

  initial begin
    forever begin
      @(posedge clk);
      if (!rst && core_dbus.valid && core_dbus.write_en && sim_halt_selected) begin
        repeat (ClocksPerBit * 12) @(posedge clk);
        $write("\n");
        $display("top_sim: halt code 0x%08h pc=0x%08h", core_dbus.write_data, pc);
        $finish;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst && halted) begin
      $fatal(1, "top_sim: core halted before firmware wrote SIM_HALT");
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge clk);
    $fatal(1, "top_sim: watchdog timeout after %0d cycles", TimeoutCycles);
  end

endmodule
