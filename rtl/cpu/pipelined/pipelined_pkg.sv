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
    logic   valid;  // slot contains an instruction
    pc_t    pc;     // PC associated with instr
    instr_u instr;  // fetched instruction
  } if_id_t;

  typedef struct packed {
    logic      valid;     // slot contains an instruction
    pc_t       pc;        // PC associated with instr
    instr_u    instr;     // decoded instruction
    control_t  ctrl;      // decoded control signals
    reg_data_t rs1_data;  // register source 1 value
    reg_data_t rs2_data;  // register source 2 value
    imm_t      imm;       // decoded immediate value
    regaddr_t  rd;        // destination register address
  } id_ex_t;

  typedef struct packed {
    logic      valid;           // slot contains an instruction
    pc_t       pc;              // PC associated with instr
    control_t  ctrl;            // control signals carried into memory
    alu_data_t alu_result;      // raw ALU output
    reg_data_t execute_result;  // value selected before memory/writeback
    mem_data_t write_data;      // store data before LSU alignment
    regaddr_t  rd;              // destination register address
  } ex_mem_t;

  typedef struct packed {
    logic      valid;   // slot contains an instruction
    control_t  ctrl;    // control signals carried into writeback
    reg_data_t result;  // final register writeback value
    regaddr_t  rd;      // destination register address
  } mem_wb_t;

endpackage
