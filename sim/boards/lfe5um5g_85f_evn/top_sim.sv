`timescale 1ns / 1ps

module top_sim #(
  parameter string ImemInitFile = "",
  parameter int unsigned ImemDepthWords = 512,
  parameter int unsigned DmemDepthWords = 512,
  parameter string DmemInitFile = "",
  parameter int unsigned ClocksPerBit = 104,
  parameter riscv_pkg::word_t SimHaltAddr = 32'h1000_f000,
  parameter int unsigned TimeoutCycles = 1_000_000
);
  localparam realtime ClkPeriod = 10ns;

  logic clk;
  logic rst;
  riscv_pkg::pc_t pc;
  riscv_pkg::instr_u instr;
  logic mem_write;
  riscv_pkg::word_t mem_addr;
  riscv_pkg::word_t mem_write_data;
  riscv_pkg::word_t mem_read_data;
  riscv_pkg::word_t led_read_data;
  riscv_pkg::word_t uart_read_data;
  riscv_pkg::word_t lsu_read_data;
  riscv_pkg::mem_size_t mem_size;
  logic mem_unsigned;
  logic [7:0] led;
  logic [7:0] led_prev;
  logic led_selected;
  logic uart_selected;
  logic sim_halt_selected;
  logic mmio_selected;
  logic halted;
  logic uart_tx;

  assign sim_halt_selected = (mem_addr == SimHaltAddr);
  assign mmio_selected = led_selected | uart_selected | sim_halt_selected;
  assign mem_read_data =
      led_selected ? led_read_data : (uart_selected ? uart_read_data : (sim_halt_selected ? '0 : lsu_read_data));

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
    .addr (pc),
    .instr(instr.raw)
  );

  core core_i (
    .clk(clk),
    .rst(rst),
    .instr(instr),
    .pc(pc),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .mem_read_data(mem_read_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned),
    .halted(halted)
  );

  led_mmio led_mmio_i (
    .clk(clk),
    .rst(rst),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(led_selected),
    .read_data(led_read_data),
    .led(led)
  );

  uart_mmio #(
    .ClocksPerBit(ClocksPerBit)
  ) uart_mmio_i (
    .clk(clk),
    .rst(rst),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(uart_selected),
    .read_data(uart_read_data),
    .tx(uart_tx)
  );

  lsu #(
    .DepthWords(DmemDepthWords),
    .InitFile  (DmemInitFile)
  ) lsu_i (
    .clk(clk),
    .mem_write(mem_write & !mmio_selected),
    .addr(mem_addr),
    .write_data(mem_write_data),
    .read_data(lsu_read_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned)
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

  always_ff @(posedge clk) begin
    if (!rst && mem_write && sim_halt_selected) begin
      $write("\n");
      $display("top_sim: halt code 0x%08h", mem_write_data);
      $finish;
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
