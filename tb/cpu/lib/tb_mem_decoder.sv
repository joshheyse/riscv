// tb_mem_decoder.sv - directed checks for load/store width decode.
//
//   make sim TB=mem_decoder
//   make wave TB=mem_decoder

`timescale 1ns / 1ps

module tb_mem_decoder
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 100_000;
  localparam int unsigned MaxPrintedFailures = 20;

  instr_u      _instr;
  mem_size_e   _mem_size;
  logic        _mem_unsigned;
  logic        _mem_op_illegal;

  int unsigned errors = 0;
  int unsigned checks = 0;
  int unsigned printed = 0;

  mem_decoder _dut (
    .instr(_instr),
    .mem_size(_mem_size),
    .mem_unsigned(_mem_unsigned),
    .mem_op_illegal(_mem_op_illegal)
  );

  function automatic instr_t encode(input opcode_e opcode, input funct3_t funct3);
    return {17'b0, funct3, 5'b0, opcode};
  endfunction

  function automatic string mem_size_name(input mem_size_e size);
    case (size)
      MEM_SIZE_BYTE: return "MEM_SIZE_BYTE";
      MEM_SIZE_HALF: return "MEM_SIZE_HALF";
      MEM_SIZE_WORD: return "MEM_SIZE_WORD";
      default:       return $sformatf("<%02b>", size);
    endcase
  endfunction

  task automatic fail(input string msg);
    errors++;
    if (printed < MaxPrintedFailures) begin
      printed++;
      $display("  FAIL %s", msg);
    end else if (printed == MaxPrintedFailures) begin
      printed++;
      $display("  ... further failures suppressed; summary counts are exact");
    end
  endtask

  task automatic check(input opcode_e opcode, input funct3_t funct3, input mem_size_e exp_size,
                       input logic exp_unsigned, input logic exp_illegal, input string what);
    _instr.raw = encode(opcode, funct3);
    #1;
    checks++;
    if (_mem_size !== exp_size || _mem_unsigned !== exp_unsigned || _mem_op_illegal !== exp_illegal) begin
      fail($sformatf(
           "%s opcode=%07b funct3=%03b: got %s unsigned=%b illegal=%b, expected %s unsigned=%b illegal=%b",
           what,
           opcode,
           funct3,
           mem_size_name(
               _mem_size
           ),
           _mem_unsigned,
           _mem_op_illegal,
           mem_size_name(
               exp_size
           ),
           exp_unsigned,
           exp_illegal
           ));
    end
  endtask

  initial begin
    check(OP_LOAD, MEM_BYTE, MEM_SIZE_BYTE, 1'b0, 1'b0, "lb");
    check(OP_LOAD, MEM_HALF, MEM_SIZE_HALF, 1'b0, 1'b0, "lh");
    check(OP_LOAD, MEM_WORD, MEM_SIZE_WORD, 1'b0, 1'b0, "lw");
    check(OP_LOAD, MEM_BYTEU, MEM_SIZE_BYTE, 1'b1, 1'b0, "lbu");
    check(OP_LOAD, MEM_HALFU, MEM_SIZE_HALF, 1'b1, 1'b0, "lhu");
    check(OP_LOAD, 3'b011, MEM_SIZE_WORD, 1'b0, 1'b1, "reserved load funct3 011");
    check(OP_LOAD, 3'b110, MEM_SIZE_WORD, 1'b0, 1'b1, "reserved load funct3 110");
    check(OP_LOAD, 3'b111, MEM_SIZE_WORD, 1'b0, 1'b1, "reserved load funct3 111");

    check(OP_STORE, MEM_BYTE, MEM_SIZE_BYTE, 1'b0, 1'b0, "sb");
    check(OP_STORE, MEM_HALF, MEM_SIZE_HALF, 1'b0, 1'b0, "sh");
    check(OP_STORE, MEM_WORD, MEM_SIZE_WORD, 1'b0, 1'b0, "sw");
    check(OP_STORE, 3'b011, MEM_SIZE_WORD, 1'b0, 1'b1, "reserved store funct3 011");
    check(OP_STORE, MEM_BYTEU, MEM_SIZE_WORD, 1'b0, 1'b1, "reserved store funct3 100");
    check(OP_STORE, MEM_HALFU, MEM_SIZE_WORD, 1'b0, 1'b1, "reserved store funct3 101");
    check(OP_STORE, 3'b110, MEM_SIZE_WORD, 1'b0, 1'b1, "reserved store funct3 110");
    check(OP_STORE, 3'b111, MEM_SIZE_WORD, 1'b0, 1'b1, "reserved store funct3 111");

    check(OP_R, MEM_BYTEU, MEM_SIZE_WORD, 1'b0, 1'b0, "non-memory default");

    if (errors == 0) begin
      $display("tb_mem_decoder: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_mem_decoder: FAIL (%0d/%0d checks failed)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutNs);
    $error("tb_mem_decoder: timeout after %0d ns", TimeoutNs);
    $fatal(1);
  end

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_mem_decoder);
    end
  end

endmodule
