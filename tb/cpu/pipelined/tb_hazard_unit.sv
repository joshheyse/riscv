// tb_hazard_unit.sv - directed checks for forwarding-aware hazard detection.
//
//   make sim DESIGN=pipelined TB=hazard_unit
//   make wave DESIGN=pipelined TB=hazard_unit

`timescale 1ns / 1ps

module tb_hazard_unit
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam int unsigned TimeoutSteps = 100;

  if_id_t      _if_id;
  id_ex_t      _id_ex;
  ex_mem_t     _ex_mem;
  logic        _stall;

  int unsigned errors = 0;
  int unsigned checks = 0;

  hazard_unit _dut (
    .if_id (_if_id),
    .id_ex (_id_ex),
    .ex_mem(_ex_mem),
    .stall(_stall)
  );

  task automatic expect_stall(input logic exp, input string what);
    checks++;
    #1;
    if (_stall !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, _stall, exp);
    end
  endtask

  task automatic clear_inputs();
    _if_id = '0;
    _id_ex = '0;
    _ex_mem = '0;
    _ex_mem.ctrl.writeback_result = WB_RESULT_EXEC;
  endtask

  task automatic set_consumer(input instr_t instr);
    _if_id.valid = 1'b1;
    _if_id.slot.instr.raw = instr;
  endtask

  task automatic set_id_ex_producer(input regaddr_t rd);
    _id_ex.valid = 1'b1;
    _id_ex.ctrl.reg_write_en = 1'b1;
    _id_ex.slot.instr.r.rd = rd;
  endtask

  task automatic set_ex_mem_producer(input regaddr_t rd, input writeback_result_e writeback_result);
    _ex_mem.valid = 1'b1;
    _ex_mem.ctrl.reg_write_en = 1'b1;
    _ex_mem.rd = rd;
    _ex_mem.ctrl.writeback_result = writeback_result;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_hazard_unit);
    end

    clear_inputs();
    expect_stall(1'b0, "invalid IF/ID does not stall");

    clear_inputs();
    set_consumer(32'h0010_8133);  // add x2, x1, x1
    set_id_ex_producer(5'd1);
    expect_stall(1'b1, "R-type rs1/rs2 hazard against ID/EX stalls");

    clear_inputs();
    set_consumer(32'h0010_8133);  // add x2, x1, x1
    set_ex_mem_producer(5'd1, WB_RESULT_EXEC);
    expect_stall(1'b0, "R-type rs1/rs2 hazard against EX/MEM ALU forwards");

    clear_inputs();
    set_consumer(32'h0010_8133);  // add x2, x1, x1
    set_ex_mem_producer(5'd1, WB_RESULT_MEM);
    expect_stall(1'b1, "R-type rs1/rs2 hazard against EX/MEM load stalls");

    clear_inputs();
    set_consumer(32'h0010_8133);  // add x2, x1, x1
    set_id_ex_producer(5'd3);
    set_ex_mem_producer(5'd4, WB_RESULT_EXEC);
    expect_stall(1'b0, "unrelated producer registers do not stall");

    clear_inputs();
    set_consumer(32'h0010_2093);  // addi x1, x0, 1
    set_id_ex_producer(5'd1);
    expect_stall(1'b0, "I-ALU ignores rs2-looking bits");

    clear_inputs();
    set_consumer(32'h0000_2083);  // lw x1, 0(x0)
    set_id_ex_producer(5'd1);
    expect_stall(1'b0, "load ignores rs2-looking bits");

    clear_inputs();
    set_consumer(32'h0010_2023);  // sw x1, 0(x0)
    set_id_ex_producer(5'd1);
    expect_stall(1'b1, "store-data rs2 hazard stalls");

    clear_inputs();
    set_consumer(32'h0020_a023);  // sw x2, 0(x1)
    set_id_ex_producer(5'd1);
    expect_stall(1'b1, "store-address rs1 hazard stalls");

    clear_inputs();
    set_consumer(32'h0000_8863);  // beq x1, x0, 16
    set_ex_mem_producer(5'd1, WB_RESULT_EXEC);
    expect_stall(1'b0, "branch rs1 hazard against EX/MEM ALU forwards in execute");

    clear_inputs();
    set_consumer(32'h0000_82e7);  // jalr x5, 0(x1)
    set_id_ex_producer(5'd1);
    expect_stall(1'b1, "jalr base rs1 hazard stalls");

    clear_inputs();
    set_consumer(32'h0000_8137);  // lui x2, 0x8; raw bits look like rs1=x1
    set_id_ex_producer(5'd1);
    expect_stall(1'b0, "lui does not use rs1-looking bits");

    clear_inputs();
    set_consumer(32'h0000_016f);  // jal x2, 0; raw bits look like rs1=x0/rs2=x0
    set_id_ex_producer(5'd2);
    expect_stall(1'b0, "jal does not use source registers");

    clear_inputs();
    set_consumer(32'h0000_0133);  // add x2, x0, x0
    set_id_ex_producer(5'd0);
    set_ex_mem_producer(5'd0, WB_RESULT_EXEC);
    expect_stall(1'b0, "x0 producer does not stall");

    clear_inputs();
    set_consumer(32'h0010_8133);  // add x2, x1, x1
    _id_ex.valid = 1'b1;
    _id_ex.ctrl.reg_write_en = 1'b0;
    _id_ex.slot.instr.r.rd = 5'd1;
    expect_stall(1'b0, "non-writing producer does not stall");

    if (errors == 0) begin
      $display("tb_hazard_unit: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_hazard_unit: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutSteps) #1;
    $display("tb_hazard_unit: TIMEOUT after %0d steps", TimeoutSteps);
    $fatal(1);
  end

endmodule
