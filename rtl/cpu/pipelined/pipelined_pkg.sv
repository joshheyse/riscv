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
    logic        valid;     // slot contains an instruction or fetch trap
    instr_slot_t slot;      // fetched instruction and PC
    trap_req_t   trap_req;  // synchronous fault detected during fetch
  } if_id_t;

  typedef struct packed {
    logic        valid;        // slot contains an instruction
    instr_slot_t slot;         // decoded instruction and PC
    control_t    ctrl;         // decoded control signals
    word_t       rs1_operand;  // register source 1 value
    word_t       rs2_operand;  // register source 2 value
    word_t       imm;          // decoded immediate value
    trap_stage_t trap;
  } id_ex_t;

  typedef struct packed {
    logic        valid;           // slot contains an instruction
    pc_t         pc;              // PC associated with instr
    control_t    ctrl;            // control signals carried into memory
    word_t       alu_result;      // raw ALU output
    word_t       execute_result;  // value selected before memory/writeback
    word_t       write_data;      // store data before LSU alignment
    regaddr_t    rd;              // destination register address
    trap_stage_t trap;
  } ex_mem_t;

  typedef struct packed {
    logic        valid;   // slot contains an instruction
    control_t    ctrl;    // control signals carried into writeback
    word_t       result;  // final register writeback value
    regaddr_t    rd;      // destination register address
    trap_stage_t trap;
  } mem_wb_t;

  typedef enum logic [1:0] {
    STAGE_ADVANCE = 2'b00,
    STAGE_HOLD    = 2'b01,
    STAGE_FLUSH   = 2'b10
  } stage_ctrl_e;

  typedef struct packed {
    stage_ctrl_e fetch;   // instruction fetch request control
    stage_ctrl_e if_id;   // IF/ID register control
    stage_ctrl_e id_ex;   // ID/EX register control
    stage_ctrl_e ex_mem;  // EX/MEM register control
    stage_ctrl_e mem_wb;  // MEM/WB register control
  } pipeline_ctrl_t;

  typedef struct packed {
    logic      en;          // instruction accesses a CSR
    logic      write_en;    // instruction writes CSR state
    csr_addr_u addr;        // addressed CSR
    csr_data_t read_data;   // current CSR value
    csr_data_t write_data;  // next CSR value
    csr_data_t result;      // value returned to integer writeback
    logic      illegal;     // addressed CSR is unsupported or not writable
  } csr_pipe_t;

  typedef struct packed {
    logic valid;
    pc_t  pc;
  } redirect_t;

  typedef enum logic [2:0] {
    FLOW_ACTION_NONE,
    FLOW_ACTION_REDIRECT,
    FLOW_ACTION_TRAP,
    FLOW_ACTION_MRET,
    FLOW_ACTION_SRET
  } flow_action_e;

  typedef struct packed {
    flow_action_e action;
    redirect_t    redirect;
  } flow_ctrl_t;

  typedef struct packed {
    logic trap;
    logic mret;
    logic sret;
  } retire_ctrl_t;

  function automatic logic writes_rd(input logic valid, input logic reg_write_en,
                                     input regaddr_t rd);
    return valid && reg_write_en && (rd != 5'd0);
  endfunction

endpackage
