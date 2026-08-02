`timescale 1ns / 1ps

// Types that define the pipelined core's stage-register boundaries.
//
// Each struct is the state carried from one stage to the next on a clock edge.
// `valid` marks whether the slot contains an instruction that should continue
// through the pipe; clearing `valid` injects a bubble or flushes wrong-path
// work. Keeping these bundles here makes the top-level core wiring readable and
// gives testbenches stable names for checking pipeline movement.
//
package pipelined_pkg;

  import riscv_pkg::*;

  typedef struct packed {
    logic   valid;
    pc_t    pc;
    instr_u instr;
  } if_id_t;

  typedef struct packed {
    logic     valid;
    pc_t      pc;
    instr_u   instr;
    control_t ctrl;
    word_t    rs1_data;
    word_t    rs2_data;
    word_t    imm;
    regaddr_t rd;
  } id_ex_t;

  typedef struct packed {
    logic     valid;
    pc_t      pc;
    control_t ctrl;
    word_t    alu_result;
    word_t    execute_result;
    word_t    write_data;
    regaddr_t rd;
  } ex_mem_t;

  typedef struct packed {
    logic     valid;
    control_t ctrl;
    word_t    result;
    regaddr_t rd;
  } mem_wb_t;

endpackage
