`timescale 1ns / 1ps

package riscv_pkg;
  localparam int unsigned XLEN = 32;

  typedef logic [XLEN-1:0] word_t;  // data: a register value, ALU operand
  typedef word_t pc_t;  // an instruction
  typedef logic [31:0] instr_t;  // an instruction
  typedef logic [4:0] regaddr_t;  // register file address
  typedef logic [2:0] funct3_t;
  typedef logic [6:0] funct7_t;

  typedef enum logic [6:0] {
    OP_R      = 7'b0110011,
    OP_I_ALU  = 7'b0010011,
    OP_LOAD   = 7'b0000011,
    OP_STORE  = 7'b0100011,
    OP_JAL    = 7'b1101111,
    OP_JALR   = 7'b1100111,
    OP_BRANCH = 7'b1100011,
    OP_LUI    = 7'b0110111,
    OP_AUIPC  = 7'b0010111,
    OP_SYSTEM = 7'b1110011
  } opcode_t;

  // ------------------------------------------------------------- funct3 --
  //
  // funct3 is a polymorphic field: the same three bits mean different things
  // depending on the opcode. The union below names each interpretation, so a
  // consumer says which lens it is looking through rather than reinterpreting
  // a bare vector. It documents intent; it does not enforce it -- nothing stops
  // you reading .alu on a branch instruction and getting a confident wrong
  // answer.

  // BRANCH: the condition. Bit 2 chooses which flag to consult, bit 1 selects
  // signed vs unsigned (it reaches the comparator's sngd, not branch_logic),
  // and bit 0 inverts. 01x is reserved and never branches.
  typedef struct packed {
    logic use_lt;  // funct3[2]
    logic unsgnd;  // funct3[1]
    logic invert;  // funct3[0]
  } br_funct3_t;

  // OP / OP-IMM: the ALU operation.
  //
  // These values are NOT arbitrary -- they are RISC-V's funct3 encoding for
  // OP/OP-IMM, which is what lets alu_decoder read the operation straight out
  // of the instruction with no lookup table. Renumbering this enum silently
  // breaks that decode; tb_alu_decoder is what would catch it.
  typedef enum logic [2:0] {
    ALU_ADDSUB  = 3'b000,
    ALU_SLL     = 3'b001,
    ALU_SLT     = 3'b010,
    ALU_SLTU    = 3'b011,
    ALU_XOR     = 3'b100,
    ALU_SRL_SRA = 3'b101,
    ALU_OR      = 3'b110,
    ALU_AND     = 3'b111
  } alu_select_t;

  typedef union packed {
    funct3_t     raw;  // the bits, uninterpreted
    alu_select_t alu;  // OP, OP-IMM
    br_funct3_t  br;   // BRANCH
  } funct3_u;

  // --------------------------------------------------- instruction formats --

  typedef struct packed {
    funct7_t    funct7;  // [31:25]
    logic [4:0] rs2;     // [24:20]
    logic [4:0] rs1;     // [19:15]
    funct3_u    funct3;  // [14:12]
    logic [4:0] rd;      // [11:7]
    opcode_t    opcode;  // [6:0]
  } r_type_t;

  typedef struct packed {
    logic [11:0] imm;     // [31:20]
    logic [4:0]  rs1;     // [19:15]
    funct3_u     funct3;  // [14:12]
    logic [4:0]  rd;      // [11:7]
    opcode_t     opcode;  // [6:0]
  } i_type_t;

  typedef union packed {
    instr_t  raw;
    r_type_t r;
    i_type_t i;
  } instr_u;


  typedef enum logic [2:0] {
    IMM_I = 3'b000,
    IMM_S = 3'b001,
    IMM_B = 3'b010,
    IMM_J = 3'b011,
    IMM_U = 3'b100
  } imm_src_t;

  // Which pair of operands the ALU sees. Bit 1 selects SrcA (rs1 or PC), bit 0
  // selects SrcB (rs2 or the immediate); the names below spell out the pair.
  // PC + rs2 (2'b10) is never needed by any RV32I instruction.
  typedef enum logic [1:0] {
    SRC_RS1_RS2 = 2'b00,  // R-type, and the branch comparison
    SRC_RS1_IMM = 2'b01,  // I-type ALU, load/store address, jalr target
    SRC_PC_IMM  = 2'b11   // branch/jal target, auipc
  } alu_src_t;

  // First level of the writeback mux. Three sources reach rd without touching
  // memory: the ALU's own output, the link address, and the raw immediate.
  typedef enum logic [1:0] {
    ALU_RES_ALU      = 2'b00,  // R-type, I-type ALU, auipc (PC + imm)
    ALU_RES_PC_PLUS4 = 2'b01,  // jal, jalr -- the return address
    ALU_RES_IMM      = 2'b10   // lui, which bypasses the ALU entirely
  } alu_result_src_t;

  // Second level of the writeback mux: the value chosen above, or memory.
  typedef enum logic {
    RESULT_ALU = 1'b0,
    RESULT_MEM = 1'b1   // loads
  } result_src_t;

  typedef struct packed {
    logic eq;
    logic lt;  // signed or unsigned per the comparator's sngd input
  } branch_flags_t;

  typedef enum logic {
    PC_SRC_INC     = 1'b0,
    PC_SRC_IEU_ADR = 1'b1
  } pc_src_t;

endpackage
