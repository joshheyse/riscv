`timescale 1ns / 1ps

package riscv_pkg;
  localparam int unsigned XLEN = 32;

  // RV32I architectural widths. Instruction width is fixed at 32 bits; data
  // and PC values are XLEN-wide in this RV32I core.
  typedef logic [XLEN-1:0] word_t;  // data: a register value, ALU operand
  typedef logic [(XLEN*2)-1:0] dword_t;  // data: a register value, ALU operand
  typedef logic [7:0] byte_t;
  typedef logic [15:0] half_t;
  typedef word_t pc_t;  // program counter / instruction address
  typedef word_t reg_data_t;  // register file value
  typedef word_t imm_t;  // decoded immediate value
  typedef word_t alu_data_t;  // ALU operand/result value
  typedef word_t mem_addr_t;  // data-memory or MMIO byte address
  typedef word_t mem_data_t;  // data-memory or MMIO payload
  typedef word_t csr_data_t;  // CSR read/write payload
  typedef logic [31:0] instr_t;  // an instruction
  typedef logic [4:0] regaddr_t;  // register file address
  typedef logic [11:0] csr_addr_t;  // CSR address field
  typedef logic [2:0] funct3_t;
  typedef logic [6:0] funct7_t;
  typedef logic [3:0] mem_write_mask_t;

  // RV32I opcode map used by the main decoder.
  //
  //   opcode   category
  //   -------  ----------------
  //   0110011  OP      R-type ALU
  //   0010011  OP-IMM  I-type ALU
  //   0000011  LOAD
  //   0100011  STORE
  //   1100011  BRANCH
  //   1101111  JAL
  //   1100111  JALR
  //   0110111  LUI
  //   0010111  AUIPC
  //   1110011  SYSTEM  currently inert
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
    OP_SYSTEM = 7'b1110011,
    OP_FENCE  = 7'b0001111
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

  typedef enum logic [2:0] {
    MEM_BYTE  = 3'b000,  // LB / SB
    MEM_HALF  = 3'b001,  // LH / SH
    MEM_WORD  = 3'b010,  // LW / SW
    MEM_BYTEU = 3'b100,  // LBU
    MEM_HALFU = 3'b101   // LHU
  } mem_funct3_t;

  typedef union packed {
    funct3_t     raw;  // the bits, uninterpreted
    alu_select_t alu;  // OP, OP-IMM
    br_funct3_t  br;   // BRANCH
    mem_funct3_t mem;  // LOAD, STORE
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

  typedef struct packed {
    instr_u instr;
    pc_t    pc;
  } instr_slot_t;

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
    ALU_SRC_RS1_RS2 = 2'b00,  // R-type, and the branch comparison
    ALU_SRC_RS1_IMM = 2'b01,  // I-type ALU, load/store address, jalr target
    ALU_SRC_PC_IMM  = 2'b11   // branch/jal target, auipc
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

  typedef enum logic [1:0] {
    MEM_SIZE_BYTE,
    MEM_SIZE_HALF,
    MEM_SIZE_WORD
  } mem_size_t;

  typedef struct packed {
    logic            reg_write_en;
    logic            mem_write_en;
    imm_src_t        imm_src;
    alu_src_t        alu_src;
    alu_result_src_t alu_result_src;
    alu_select_t     alu_select;
    result_src_t     result_src;
    logic            sub_arith;
    pc_src_t         pc_src;
    logic            branch_sgnd;
    mem_size_t       mem_size;
    logic            mem_unsigned;
    logic            clear_pc_lsb;
    logic            illegal_instr;
  } control_t;

  typedef enum logic [1:0] {
    EXT_STATUS_OFF     = 2'b00,
    EXT_STATUS_INITIAL = 2'b01,
    EXT_STATUS_CLEAN   = 2'b10,
    EXT_STATUS_DIRTY   = 2'b11
  } ext_status_t;

  typedef enum logic [1:0] {
    MPP_USER       = 2'b00,
    MPP_SUPERVISOR = 2'b01,
    MPP_MACHINE    = 2'b11
  } mpp_t;

  typedef enum logic [1:0] {
    CBIE_NONE     = 2'b00,
    CBIE_FLUSH    = 2'b01,
    CBIE_RESERVED = 2'b10,
    CBIE_INVAL    = 2'b11
  } cbie_t;

  typedef struct packed {
    logic [25:0] wpri5;  // [31:6] write-preserved, reads ignored
    logic        mbe;    // [5] machine big-endian mode
    logic        sbe;    // [4] supervisor big-endian mode
    logic [3:0]  wpri4;  // [3:0] write-preserved, reads ignored
  } mstatush_t;

  typedef struct packed {
    logic        sd;     // [31] extension dirty summary
    logic [7:0]  wpri3;  // [30:23] write-preserved, reads ignored
    logic        tsr;    // [22] trap SRET
    logic        tw;     // [21] timeout wait
    logic        tvm;    // [20] trap virtual-memory management
    logic        mxr;    // [19] make executable readable
    logic        sum;    // [18] permit S-mode user-memory access
    logic        mprv;   // [17] modify privilege for data accesses
    ext_status_t xs;     // [16:15] user extension status
    ext_status_t fs;     // [14:13] floating-point status
    mpp_t        mpp;    // [12:11] previous machine privilege
    ext_status_t vs;     // [10:9] vector extension status
    logic        spp;    // [8] previous supervisor privilege
    logic        mpie;   // [7] previous machine interrupt enable
    logic        ube;    // [6] user big-endian mode
    logic        spie;   // [5] previous supervisor interrupt enable
    logic        wpri2;  // [4] write-preserved, reads ignored
    logic        mie;    // [3] machine interrupt enable
    logic        wpri1;  // [2] write-preserved, reads ignored
    logic        sie;    // [1] supervisor interrupt enable
    logic        wpri0;  // [0] write-preserved, reads ignored
  } mstatus_t;

  typedef struct packed {
    logic        sd;     // [31] extension dirty summary
    logic [10:0] wpri5;  // [30:20] write-preserved, reads ignored
    logic        mxr;    // [19] make executable readable
    logic        sum;    // [18] permit S-mode user-memory access
    logic        wpri4;  // [17] write-preserved, reads ignored
    ext_status_t xs;     // [16:15] user extension status
    ext_status_t fs;     // [14:13] floating-point status
    logic [1:0]  wpri3;  // [12:11] write-preserved, reads ignored
    ext_status_t vs;     // [10:9] vector extension status
    logic        spp;    // [8] previous supervisor privilege
    logic        wpri2;  // [7] write-preserved, reads ignored
    logic        ube;    // [6] user big-endian mode
    logic        spie;   // [5] previous supervisor interrupt enable
    logic [2:0]  wpri1;  // [4:2] write-preserved, reads ignored
    logic        sie;    // [1] supervisor interrupt enable
    logic        wpri0;  // [0] write-preserved, reads ignored
  } sstatus_t;

  typedef struct packed {
    logic [23:0] wpri1;  // [31:8] write-preserved, reads ignored
    logic        cbze;   // [7] cache-block zero instruction enable
    logic        cbcfe;  // [6] cache-block clean/flush instruction enable
    cbie_t       cbie;   // [5:4] cache-block invalidate instruction enable
    logic        sse;    // [3] shadow stack enable
    logic        lpe;    // [2] landing pad enable
    logic        wpri0;  // [1] write-preserved, reads ignored
    logic        fiom;   // [0] fence of I/O implies memory
  } envcfg_t;

  typedef envcfg_t senvcfg_t;
  typedef envcfg_t menvcfg_t;

  typedef struct packed {
    logic        stce;   // [31] supervisor timer compare enable
    logic        pbmte;  // [30] page-based memory types enable
    logic        adue;   // [29] hardware A/D PTE update enable
    logic [28:0] wpri2;  // [28:0] write-preserved, reads ignored
  } menvcfgh_t;

  typedef struct packed {
    logic [15:0] platform;  // [31:16] platform/custom interrupt pending
    logic [3:0]  wpri5;     // [15:12] write-preserved, reads ignored
    logic        meip;      // [11] machine external interrupt pending
    logic        wpri4;     // [10] write-preserved, reads ignored
    logic        seip;      // [9] supervisor external interrupt pending
    logic        wpri3;     // [8] write-preserved, reads ignored
    logic        mtip;      // [7] machine timer interrupt pending
    logic        wpri2;     // [6] write-preserved, reads ignored
    logic        stip;      // [5] supervisor timer interrupt pending
    logic        wpri1;     // [4] write-preserved, reads ignored
    logic        msip;      // [3] machine software interrupt pending
    logic        wpri0;     // [2] write-preserved, reads ignored
    logic        ssip;      // [1] supervisor software interrupt pending
    logic        usip;      // [0] user software interrupt pending
  } mip_t;

endpackage
