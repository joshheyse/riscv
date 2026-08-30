`timescale 1ns / 1ps

package riscv_pkg;
  localparam int unsigned XLEN = 32;

  // Number of bits needed to index `count` elements. Packed types cannot have
  // zero width, so a single-element collection still receives a one-bit index.
  function automatic int unsigned index_width(input int unsigned count);
    return (count > 1) ? $clog2(count) : 1;
  endfunction

  // RV32I architectural widths. Instruction width is fixed at 32 bits; data
  // and PC values are XLEN-wide in this RV32I core.
  typedef logic [XLEN-1:0] word_t;  // data: a register value, ALU operand
  typedef logic [(XLEN*2)-1:0] dword_t;  // data: a register value, ALU operand
  typedef logic [7:0] byte_t;
  typedef logic [15:0] half_t;
  typedef word_t pc_t;  // program counter / instruction address
  typedef word_t reg_data_t;  // register file value
  typedef word_t imm_t;  // decoded immediate value
  typedef word_t integer_data_t;  // integer execution operand/result value
  typedef word_t mem_addr_t;  // data-memory or MMIO byte address
  typedef word_t mem_data_t;  // data-memory or MMIO payload
  typedef struct packed {
    mem_addr_t start_addr;  // inclusive base address
    mem_addr_t end_addr;    // exclusive upper bound
    logic      writeable;   // write enable allowed for this source
  } mmio_source_t;
  typedef word_t csr_data_t;  // CSR read/write payload
  typedef logic [31:0] instr_t;  // an instruction
  typedef logic [4:0] regaddr_t;  // register file address
  typedef logic [4:0] csr_zimm_t;  // CSR immediate operand field
  typedef logic [11:0] csr_addr_raw_t;  // raw CSR address bits

  typedef enum logic [1:0] {
    PRIV_USER       = 2'b00,
    PRIV_SUPERVISOR = 2'b01,
    PRIV_MACHINE    = 2'b11
  } priv_mode_e;

  typedef enum csr_addr_raw_t {
    CSR_SSTATUS    = 12'h100,
    CSR_SIE        = 12'h104,
    CSR_STVEC      = 12'h105,
    CSR_SCOUNTEREN = 12'h106,
    CSR_SENVCFG    = 12'h10a,
    CSR_SSCRATCH   = 12'h140,
    CSR_SEPC       = 12'h141,
    CSR_SCAUSE     = 12'h142,
    CSR_STVAL      = 12'h143,
    CSR_SIP        = 12'h144,
    CSR_SATP       = 12'h180,
    CSR_MSTATUS    = 12'h300,
    CSR_MISA       = 12'h301,
    CSR_MEDELEG    = 12'h302,
    CSR_MIDELEG    = 12'h303,
    CSR_MIE        = 12'h304,
    CSR_MTVEC      = 12'h305,
    CSR_MCOUNTEREN = 12'h306,
    CSR_MENVCFG    = 12'h30a,
    CSR_MSTATUSH   = 12'h310,
    CSR_MENVCFGH   = 12'h31a,
    CSR_MSCRATCH   = 12'h340,
    CSR_MEPC       = 12'h341,
    CSR_MCAUSE     = 12'h342,
    CSR_MTVAL      = 12'h343,
    CSR_MIP        = 12'h344,
    CSR_PMPCFG0    = 12'h3a0,
    CSR_PMPCFG1    = 12'h3a1,
    CSR_PMPCFG2    = 12'h3a2,
    CSR_PMPCFG3    = 12'h3a3,
    CSR_PMPADDR0   = 12'h3b0,
    CSR_PMPADDR1   = 12'h3b1,
    CSR_PMPADDR2   = 12'h3b2,
    CSR_PMPADDR3   = 12'h3b3,
    CSR_PMPADDR4   = 12'h3b4,
    CSR_PMPADDR5   = 12'h3b5,
    CSR_PMPADDR6   = 12'h3b6,
    CSR_PMPADDR7   = 12'h3b7,
    CSR_PMPADDR8   = 12'h3b8,
    CSR_PMPADDR9   = 12'h3b9,
    CSR_PMPADDR10  = 12'h3ba,
    CSR_PMPADDR11  = 12'h3bb,
    CSR_PMPADDR12  = 12'h3bc,
    CSR_PMPADDR13  = 12'h3bd,
    CSR_PMPADDR14  = 12'h3be,
    CSR_PMPADDR15  = 12'h3bf,
    CSR_MCYCLE     = 12'hb00,
    CSR_MINSTRET   = 12'hb02,
    CSR_MCYCLEH    = 12'hb80,
    CSR_MINSTRETH  = 12'hb82,
    CSR_CYCLE      = 12'hc00,
    CSR_TIME       = 12'hc01,
    CSR_INSTRET    = 12'hc02,
    CSR_CYCLEH     = 12'hc80,
    CSR_TIMEH      = 12'hc81,
    CSR_INSTRETH   = 12'hc82,
    CSR_MVENDORID  = 12'hf11,
    CSR_MARCHID    = 12'hf12,
    CSR_MIMPID     = 12'hf13,
    CSR_MHARTID    = 12'hf14
  } csr_addr_e;

  typedef struct packed {
    logic [1:0] rw;        // [11:10] read/write class; 2'b11 is read-only
    priv_mode_e min_priv;  // [9:8] minimum privilege required by CSR address
    logic [7:0] index;     // [7:0] CSR index within the privilege/class space
  } csr_addr_fields_t;

  typedef union packed {
    csr_addr_raw_t    raw;     // full 12-bit CSR address
    csr_addr_e        named;   // known CSR address enum view
    csr_addr_fields_t fields;  // decoded CSR address fields
  } csr_addr_u;

  typedef logic [2:0] funct3_t;
  typedef logic [6:0] funct7_t;
  typedef logic [3:0] mem_write_mask_t;

  typedef struct packed {
    logic            valid;       // request valid; one request at a time
    logic            write_en;    // 1 = write/store transaction, 0 = read/load
    mem_addr_t       addr;        // target byte address
    mem_data_t       write_data;  // write payload
    mem_write_mask_t write_mask;  // active byte lanes for writes
  } mem_req_t;

  typedef struct packed {
    logic      valid;      // response data is on the bus this cycle
    mem_data_t read_data;  // read payload when valid=1 and write_en=0
  } mem_rsp_t;

  typedef word_t tval_t;

  localparam int unsigned PmpNumEntries = 16;

  typedef enum logic [1:0] {
    PMP_ADDR_OFF   = 2'b00,
    PMP_ADDR_TOR   = 2'b01,
    PMP_ADDR_NA4   = 2'b10,
    PMP_ADDR_NAPOT = 2'b11
  } pmp_addr_match_e;

  typedef struct packed {
    logic            locked;
    logic       [1:0] reserved;
    pmp_addr_match_e addr_match;
    logic            execute;
    logic            write;
    logic            read;
  } pmp_cfg_t;

  typedef word_t pmp_addr_t;

  typedef struct packed {
    logic        valid;
    logic        locked;
    logic        execute;
    logic        write;
    logic        read;
    logic [34:0] start;
    logic [34:0] end_addr;
  } pmp_region_t;

  typedef struct packed {
    pmp_region_t [PmpNumEntries-1:0] entries;
  } pmp_region_state_t;

  typedef struct packed {
    pmp_cfg_t  [PmpNumEntries-1:0] cfg;
    pmp_addr_t [PmpNumEntries-1:0] addr;
  } pmp_state_t;

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
  //   1110011  SYSTEM
  //   0101111  AMO
  typedef enum logic [6:0] {
    OP_R        = 7'b0110011,
    OP_I_ALU    = 7'b0010011,
    OP_LOAD     = 7'b0000011,
    OP_STORE    = 7'b0100011,
    OP_JAL      = 7'b1101111,
    OP_JALR     = 7'b1100111,
    OP_BRANCH   = 7'b1100011,
    OP_LUI      = 7'b0110111,
    OP_AUIPC    = 7'b0010111,
    OP_SYSTEM   = 7'b1110011,
    OP_MISC_MEM = 7'b0001111,
    OP_AMO      = 7'b0101111
  } opcode_e;

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
  } alu_op_e;

  typedef enum logic [2:0] {
    MEM_BYTE  = 3'b000,  // LB / SB
    MEM_HALF  = 3'b001,  // LH / SH
    MEM_WORD  = 3'b010,  // LW / SW
    MEM_BYTEU = 3'b100,  // LBU
    MEM_HALFU = 3'b101   // LHU
  } mem_funct3_e;

  typedef enum logic [2:0] {
    SYS_F3_PRIV = 3'b000,  // ecall, ebreak, mret, wfi, etc.
    SYS_F3_RW   = 3'b001,  // csrrw
    SYS_F3_RS   = 3'b010,  // csrrs
    SYS_F3_RC   = 3'b011,  // csrrc
    SYS_F3_RWI  = 3'b101,  // csrrwi
    SYS_F3_RSI  = 3'b110,  // csrrsi
    SYS_F3_RCI  = 3'b111   // csrrci
  } sys_funct3_e;

  typedef enum logic [2:0] {AMO_F3_WORD = 3'b010} amo_funct3_e;

  // Atomic-memory operation selected by an OP-AMO instruction. These are the
  // ISA-defined funct5 encodings in instruction bits [31:27].
  typedef enum logic [4:0] {
    AMO_OP_ADD  = 5'b00000,
    AMO_OP_SWAP = 5'b00001,
    AMO_OP_LR   = 5'b00010,
    AMO_OP_SC   = 5'b00011,
    AMO_OP_XOR  = 5'b00100,
    AMO_OP_OR   = 5'b01000,
    AMO_OP_AND  = 5'b01100,
    AMO_OP_MIN  = 5'b10000,
    AMO_OP_MAX  = 5'b10100,
    AMO_OP_MINU = 5'b11000,
    AMO_OP_MAXU = 5'b11100
  } amo_op_e;

  typedef enum logic [11:0] {
    SYS_IMM_ECALL  = 12'h000,
    SYS_IMM_EBREAK = 12'h001,
    SYS_IMM_SRET   = 12'h102,
    SYS_IMM_WFI    = 12'h105,
    SYS_IMM_MRET   = 12'h302
  } sys_imm_e;

  typedef union packed {
    logic [11:0] raw;  // the bits, uninterpreted
    sys_imm_e    sys;  // SYSTEM privileged instruction immediate
  } imm12_u;

  typedef union packed {
    funct3_t     raw;  // the bits, uninterpreted
    alu_op_e     alu;  // OP, OP-IMM
    br_funct3_t  br;   // BRANCH
    mem_funct3_e mem;  // LOAD, STORE
    sys_funct3_e sys;  // SYSTEM
  } funct3_u;

  // --------------------------------------------------- instruction formats --

  typedef struct packed {
    funct7_t    funct7;  // [31:25]
    logic [4:0] rs2;     // [24:20]
    logic [4:0] rs1;     // [19:15]
    funct3_u    funct3;  // [14:12]
    logic [4:0] rd;      // [11:7]
    opcode_e    opcode;  // [6:0]
  } r_type_t;

  typedef struct packed {
    amo_op_e     op;      // [31:27]
    logic        aq;      // [26]
    logic        rl;      // [25]
    logic [4:0]  rs2;     // [24:20], x0 for LR.W
    logic [4:0]  rs1;     // [19:15], address register
    amo_funct3_e funct3;  // [14:12], AMO_F3_WORD for RV32A
    logic [4:0]  rd;      // [11:7]
    opcode_e     opcode;  // [6:0], OP_AMO
  } amo_type_t;

  typedef struct packed {
    imm12_u     imm;     // [31:20]
    logic [4:0] rs1;     // [19:15]
    funct3_u    funct3;  // [14:12]
    logic [4:0] rd;      // [11:7]
    opcode_e    opcode;  // [6:0]
  } i_type_t;

  typedef union packed {
    instr_t raw;
    r_type_t r;
    i_type_t i;
    amo_type_t amo;
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
  } imm_format_e;

  // Which pair of operands integer execution sees. Bit 1 selects SrcA (rs1 or PC), bit 0
  // selects SrcB (rs2 or the immediate); the names below spell out the pair.
  // PC + rs2 (2'b10) is never needed by any RV32I instruction.
  typedef enum logic [1:0] {
    INTEGER_OPERANDS_RS1_RS2 = 2'b00,  // register-register integer operations
    INTEGER_OPERANDS_RS1_IMM = 2'b01,  // I-type ALU, load/store address, jalr target
    INTEGER_OPERANDS_PC_IMM  = 2'b11   // branch/jal target, auipc
  } integer_operands_sel_e;

  // First level of the writeback mux. These sources reach rd without touching
  // memory: the ALU's own output, the link address, the raw immediate, or the
  // old CSR value returned by a CSR instruction.
  typedef enum logic [1:0] {
    EXEC_RESULT_ALU      = 2'b00,  // R-type, I-type ALU, auipc (PC + imm)
    EXEC_RESULT_PC_PLUS4 = 2'b01,  // jal, jalr -- the return address
    EXEC_RESULT_IMM      = 2'b10,  // lui, which bypasses the ALU entirely
    EXEC_RESULT_CSR      = 2'b11   // CSR read result
  } execute_result_e;

  // Second level of the writeback mux: the value chosen above, or memory.
  typedef enum logic {
    WB_RESULT_EXEC = 1'b0,
    WB_RESULT_MEM  = 1'b1   // loads
  } writeback_result_e;

  typedef struct packed {
    logic eq;
    logic lt;  // signed or unsigned per the comparator's sngd input
  } branch_flags_t;

  typedef enum logic {
    PC_SRC_INC     = 1'b0,
    PC_SRC_IEU_ADR = 1'b1
  } pc_src_e;

  typedef enum logic [1:0] {
    MEM_SIZE_BYTE,
    MEM_SIZE_HALF,
    MEM_SIZE_WORD
  } mem_size_e;

  typedef enum logic [1:0] {
    CSR_OP_RW,
    CSR_OP_RS,
    CSR_OP_RC
  } csr_op_e;

  typedef struct packed {
    logic    en;
    logic    write_en;
    csr_op_e op;
    logic    use_zimm;
  } csr_ctrl_t;

  typedef enum logic [2:0] {
    SYSTEM_OP_NONE,
    SYSTEM_OP_MRET,
    SYSTEM_OP_SRET,
    SYSTEM_OP_ECALL,
    SYSTEM_OP_EBREAK,
    SYSTEM_OP_WFI,
    SYSTEM_OP_ILLEGAL,
    SYSTEM_OP_SFENCE_VMA
  } system_op_e;

  typedef struct packed {
    logic       en;
    system_op_e op;
  } system_ctrl_t;

  // Decoded control-flow class. Branch and jump are mutually exclusive; the
  // branch condition itself is resolved later from funct3 and branch flags.
  typedef enum logic [1:0] {
    FLOW_NONE,
    FLOW_BRANCH,
    FLOW_JUMP
  } flow_e;

  typedef enum logic [4:0] {
    TRAP_SRC_NONE,
    TRAP_SRC_INSTR_ADDR_MISALIGNED,
    TRAP_SRC_ILLEGAL_INSTR,
    TRAP_SRC_ILLEGAL_CSR,
    TRAP_SRC_ECALL,
    TRAP_SRC_EBREAK,
    TRAP_SRC_LOAD_ADDR_MISALIGNED,
    TRAP_SRC_STORE_ADDR_MISALIGNED,
    TRAP_SRC_MACHINE_SOFTWARE_INTERRUPT,
    TRAP_SRC_MACHINE_TIMER_INTERRUPT,
    TRAP_SRC_MACHINE_EXTERNAL_INTERRUPT,
    TRAP_SRC_SUPERVISOR_SOFTWARE_INTERRUPT,
    TRAP_SRC_SUPERVISOR_TIMER_INTERRUPT,
    TRAP_SRC_SUPERVISOR_EXTERNAL_INTERRUPT,
    TRAP_SRC_INSTR_ACCESS_FAULT,
    TRAP_SRC_LOAD_ACCESS_FAULT,
    TRAP_SRC_STORE_ACCESS_FAULT,
    TRAP_SRC_INSTR_PAGE_FAULT,
    TRAP_SRC_LOAD_PAGE_FAULT,
    TRAP_SRC_STORE_PAGE_FAULT
  } trap_src_e;

  typedef struct packed {
    logic      valid;  // stage requests a trap
    trap_src_e src;    // trap source
    tval_t     tval;   // trap-specific value
  } trap_req_t;

  typedef enum logic [1:0] {
    MEM_ORDER_NONE,
    MEM_ORDER_FENCE,
    MEM_ORDER_FENCE_I,
    MEM_ORDER_SFENCE_VMA
  } mem_order_op_e;

  typedef enum logic {
    MULDIV_MUL,
    MULDIV_DIV
  } muldiv_unit_e;

  typedef enum logic [1:0] {
    MUL_OP_LOW,
    MUL_OP_HIGH_SS,
    MUL_OP_HIGH_SU,
    MUL_OP_HIGH_UU
  } mul_op_e;

  typedef enum logic [1:0] {
    DIV_OP_QUOTIENT_SIGNED,
    DIV_OP_QUOTIENT_UNSIGNED,
    DIV_OP_REMAINDER_SIGNED,
    DIV_OP_REMAINDER_UNSIGNED
  } div_op_e;

  typedef struct packed {
    logic en;
    muldiv_unit_e unit;
    mul_op_e mul_op;
    div_op_e div_op;
  } muldiv_ctrl_t;

  typedef struct packed {
    logic          valid;
    integer_data_t src_a;
    integer_data_t src_b;
    mul_op_e       op;
  } mul_req_t;

  typedef struct packed {
    logic          valid;
    integer_data_t result;
  } mul_rsp_t;

  typedef struct packed {
    alu_op_e op;         // ALU function selected by decode
    logic    sub_arith;  // use SUB/SRA variant for shared ALU op
  } alu_ctrl_t;

  typedef struct packed {
    logic    en;
    amo_op_e op;
    logic    aq;
    logic    rl;
  } amo_ctrl_t;

  typedef struct packed {
    logic                  reg_write_en;          // commit a value to integer register rd
    logic                  mem_write_en;          // issue a store on the data bus
    imm_format_e           imm_format;            // instruction immediate encoding
    alu_ctrl_t             alu;                   // integer ALU operation control
    muldiv_ctrl_t          muldiv;                // integer MUL/DIV operation control
    integer_operands_sel_e integer_operands_sel;  // integer execution operand sources
    execute_result_e       execute_result;        // execute-stage value before memory
    writeback_result_e     writeback_result;      // value committed to rd
    pc_src_e               pc_src;                // sequential PC or IEU-computed target
    logic                  branch_sgnd;           // compare branch operands as signed
    mem_size_e             mem_size;              // byte/half/word memory transfer width
    logic                  mem_unsigned;          // zero-extend load instead of sign-extend
    logic                  clear_pc_lsb;          // force JALR target bit 0 to zero
    flow_e flow;                                  // decoded branch/jump class
    trap_req_t             trap;                  // decoded synchronous trap request
    csr_ctrl_t             csr;                   // CSR read/write/set/clear control
    system_ctrl_t          system;                // privileged SYSTEM instruction control
    mem_order_op_e         mem_order;             // fence and related controls
    amo_ctrl_t             amo;
  } control_t;

  typedef enum logic [1:0] {
    EXT_STATUS_OFF     = 2'b00,
    EXT_STATUS_INITIAL = 2'b01,
    EXT_STATUS_CLEAN   = 2'b10,
    EXT_STATUS_DIRTY   = 2'b11
  } ext_status_e;

  typedef enum logic [1:0] {
    MPP_USER       = 2'b00,
    MPP_SUPERVISOR = 2'b01,
    MPP_MACHINE    = 2'b11
  } mpp_e;

  typedef enum logic [1:0] {
    CBIE_NONE     = 2'b00,
    CBIE_FLUSH    = 2'b01,
    CBIE_RESERVED = 2'b10,
    CBIE_INVAL    = 2'b11
  } cbie_e;

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
    ext_status_e xs;     // [16:15] user extension status
    ext_status_e fs;     // [14:13] floating-point status
    mpp_e        mpp;    // [12:11] previous machine privilege
    ext_status_e vs;     // [10:9] vector extension status
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
    ext_status_e xs;     // [16:15] user extension status
    ext_status_e fs;     // [14:13] floating-point status
    logic [1:0]  wpri3;  // [12:11] write-preserved, reads ignored
    ext_status_e vs;     // [10:9] vector extension status
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
    cbie_e       cbie;   // [5:4] cache-block invalidate instruction enable
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

  typedef mip_t mie_t;

  typedef enum logic [1:0] {
    TVEC_MODE_DIRECT   = 2'b00,
    TVEC_MODE_VECTORED = 2'b01
  } tvec_mode_e;

  typedef struct packed {
    logic [29:0] base;  // [31:2] trap-vector base address
    tvec_mode_e  mode;  // [1:0] trap-vector mode
  } tvec_t;

  typedef pc_t epc_t;

  typedef enum logic [30:0] {
    CAUSE_INSTR_ADDR_MISALIGNED = 31'd0,
    CAUSE_INSTR_ACCESS_FAULT    = 31'd1,
    CAUSE_ILLEGAL_INSTR         = 31'd2,
    CAUSE_BREAKPOINT            = 31'd3,
    CAUSE_LOAD_ADDR_MISALIGNED  = 31'd4,
    CAUSE_LOAD_ACCESS_FAULT     = 31'd5,
    CAUSE_STORE_ADDR_MISALIGNED = 31'd6,
    CAUSE_STORE_ACCESS_FAULT    = 31'd7,
    CAUSE_ECALL_U               = 31'd8,
    CAUSE_ECALL_S               = 31'd9,
    CAUSE_ECALL_M               = 31'd11,
    CAUSE_INSTR_PAGE_FAULT      = 31'd12,
    CAUSE_LOAD_PAGE_FAULT       = 31'd13,
    CAUSE_STORE_PAGE_FAULT      = 31'd15
  } cause_code_e;

  typedef struct packed {
    logic        is_interrupt;  // [31] 1 = interrupt, 0 = exception
    cause_code_e code;          // [30:0] exception/interrupt cause code
  } cause_t;

  typedef csr_data_t mvendorid_t;
  typedef csr_data_t marchid_t;
  typedef csr_data_t mimpid_t;
  typedef csr_data_t mhartid_t;

  typedef struct packed {
    pc_t        epc;          // PC saved in the target privilege's xepc CSR
    cause_t     cause;        // value saved in the target privilege's xcause CSR
    tval_t      tval;         // value saved in the target privilege's xtval CSR
    pc_t        handler_pc;   // resolved trap-vector target
    priv_mode_e target_priv;  // privilege mode entered by this trap
  } trap_t;

  typedef struct packed {
    logic  valid;    // trap should be taken
    trap_t payload;  // architectural trap payload
  } trap_stage_t;

  typedef enum logic {
    SATP_MODE_BARE = 1'b0,
    SATP_MODE_SV32 = 1'b1
  } satp_mode_e;

  typedef logic [8:0] sv32_asid_t;
  typedef logic [9:0] sv32_vpn_index_t;
  typedef logic [11:0] sv32_page_offset_t;
  typedef logic [9:0] sv32_ppn0_t;
  typedef logic [11:0] sv32_ppn1_t;

  typedef struct packed {
    sv32_vpn_index_t vpn1;
    sv32_vpn_index_t vpn0;
  } sv32_vpn_t;

  typedef struct packed {
    logic       valid;
    logic       all_vpns;
    sv32_vpn_t  vpn;
    logic       all_asids;
    sv32_asid_t asid;
  } tlb_flush_req_t;

  typedef struct packed {
    sv32_ppn1_t ppn1;
    sv32_ppn0_t ppn0;
  } sv32_ppn_t;

  typedef enum logic {
    SV32_LEVEL_0 = 1'b0,  // 4 KiB leaf
    SV32_LEVEL_1 = 1'b1   // 4 MiB leaf
  } sv32_level_e;

  typedef struct packed {
    satp_mode_e mode;
    sv32_asid_t asid;
    sv32_ppn_t  ppn;
  } satp_t;

  typedef struct packed {
    logic [28:0] hpm;
    logic        ir;
    logic        tm;
    logic        cy;
  } counteren_t;

  typedef struct packed {
    tvec_t      mtvec;
    tvec_t      stvec;
    mstatus_t   mstatus;
    mie_t       mie;
    mip_t       mip;
    epc_t       mepc;
    epc_t       sepc;
    word_t      medeleg;
    word_t      mideleg;
    priv_mode_e priv_mode;
    satp_t      satp;
    counteren_t mcounteren;
    counteren_t scounteren;
    // PMP CSR state is retained privately by csr_file; consumers receive
    // only the registered, access-ready region intervals.
    pmp_region_state_t pmp_regions;
  } csr_status_t;

  typedef struct packed {
    logic clean;
    logic invalidate;
  } cache_command_op_t;

`ifndef CACHE_NUM_WAYS
  `define CACHE_NUM_WAYS 4
`endif
  localparam int unsigned CacheCapacityBytes = 4096;
  localparam int unsigned CacheNumWays = `CACHE_NUM_WAYS;
  localparam int unsigned CacheWordsPerLine = 8;
  localparam int unsigned CacheNumSets =
      CacheCapacityBytes / (CacheNumWays * CacheWordsPerLine * 4);
  localparam int unsigned CacheWayIndexBits = index_width(CacheNumWays);
  localparam int unsigned CacheSetIndexBits = index_width(CacheNumSets);
  localparam int unsigned CacheWordIndexBits = index_width(CacheWordsPerLine);
  localparam int unsigned CacheLineOffsetBits = CacheWordIndexBits + 2;
  localparam int unsigned CacheDataIndexBits = CacheSetIndexBits + CacheWordIndexBits;

  typedef logic [CacheWayIndexBits-1:0] way_index_t;
  typedef logic [XLEN-CacheSetIndexBits-CacheLineOffsetBits-1:0] tag_t;
  typedef logic [CacheSetIndexBits-1:0] set_index_t;
  typedef logic [CacheWordIndexBits-1:0] word_index_t;
  typedef logic [CacheLineOffsetBits-1:0] offset_t;
  typedef logic [CacheDataIndexBits-1:0] data_index_t;
  typedef struct packed {
    tag_t tag;
    set_index_t set;
    offset_t offset;
  } cache_line_address_t;

  typedef enum logic [2:0] {
    META_NONE,         // Preserve the selected set's metadata.
    META_INSTALL,      // Write its tag, mark it valid, and clear dirty.
    META_MARK_DIRTY,   // Mark the selected valid line dirty after a store.
    META_CLEAR_DIRTY,  // Mark the selected line clean after write-back.
    META_INVALIDATE    // Clear both valid and dirty for the selected set.
  } cache_meta_op_e;

  typedef enum logic [1:0] {
    MMU_ACCESS_FETCH,
    MMU_ACCESS_LOAD,
    MMU_ACCESS_STORE
  } mmu_access_e;

  typedef enum logic [1:0] {
    MMU_FAULT_NONE,   // Translation completed successfully.
    MMU_FAULT_PAGE,   // Page-table contents or permissions rejected the access.
    MMU_FAULT_ACCESS  // Translation required an unsupported physical access.
  } mmu_fault_e;

  typedef struct packed {
    sv32_vpn_t         vpn;     // virtual address bits [31:12]
    sv32_page_offset_t offset;  // virtual address bits [11:0]
  } sv32_virtual_address_fields_t;

  typedef struct packed {
    sv32_ppn_t  ppn;             // [31:10] physical page number
    logic [1:0] rsw;             // [9:8] reserved for supervisor software
    logic       dirty;           // [7] page has been written
    logic       accessed;        // [6] page has been read, written, or fetched
    logic       global_mapping;  // [5] mapping applies to every address space
    logic       user;            // [4] page is accessible from user mode
    logic       execute;         // [3] instruction fetches are permitted
    logic       write;           // [2] stores are permitted; requires read
    logic       read;            // [1] loads are permitted
    logic       valid;           // [0] PTE contains a valid mapping or pointer
  } sv32_pte_t;

  typedef union packed {
    mem_addr_t                    raw;
    sv32_virtual_address_fields_t fields;
  } virtual_address_u;

  typedef struct packed {
    mmu_access_e access;
    priv_mode_e          privilege;
    logic                sum;
    logic                mxr;
  } translation_ctx_t;

  typedef struct packed {
    logic             valid;
    virtual_address_u virtual_addr;
    translation_ctx_t ctx;
  } mmu_req_t;

  typedef struct packed {
    logic        valid;
    mmu_fault_e  fault;
    mem_addr_t   physical_addr;
    sv32_level_e leaf_level;
    sv32_pte_t   leaf_pte;
  } mmu_rsp_t;

  typedef struct packed {
    logic            valid;       // request valid; one request at a time
    logic            write_en;    // 1 = write/store transaction, 0 = read/load
    mem_addr_t       addr;        // target byte address
    mem_size_e       size;        // architectural access width for protection checks
    mem_data_t       write_data;  // write payload
    mem_write_mask_t write_mask;  // active byte lanes for writes
  } vmem_req_t;

  typedef struct packed {
    logic       valid;          // response data is on the bus this cycle
    mem_data_t  read_data;      // read payload when valid=1 and write_en=0
    mmu_fault_e fault;
    mem_addr_t  physical_addr;  // translated address, or zero when translation faults
  } vmem_rsp_t;

  typedef struct packed {
    logic          valid;
    integer_data_t src_a;
    integer_data_t src_b;
    div_op_e       op;
  } div_req_t;

  typedef struct packed {
    logic          valid;
    integer_data_t result;
  } div_rsp_t;

  typedef struct packed {
    logic             valid;
    amo_ctrl_t        ctrl;
    virtual_address_u address;
    reg_data_t        operand;  // rs2
    translation_ctx_t ctx;
  } amo_req_t;

  typedef struct packed {
    logic       valid;
    reg_data_t  result;  // old value for LR/AMO, 0/1 for SC
    mmu_fault_e fault;
  } amo_rsp_t;

endpackage
