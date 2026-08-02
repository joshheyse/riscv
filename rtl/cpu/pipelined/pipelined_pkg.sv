`timescale 1ns / 1ps

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
