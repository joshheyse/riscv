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
  typedef struct packed {
    mem_addr_t start_addr;  // inclusive base address
    mem_addr_t end_addr;  // exclusive upper bound
    logic      writeable;  // write enable allowed for this source
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
  } priv_mode_t;

  typedef enum csr_addr_raw_t {
    CSR_SSTATUS  = 12'h100,
    CSR_SIE      = 12'h104,
    CSR_STVEC    = 12'h105,
    CSR_SENVCFG  = 12'h10a,
    CSR_SSCRATCH = 12'h140,
    CSR_SEPC     = 12'h141,
    CSR_SCAUSE   = 12'h142,
    CSR_STVAL    = 12'h143,
    CSR_SIP      = 12'h144,

    CSR_MSTATUS    = 12'h300,
    CSR_MISA       = 12'h301,
    CSR_MEDELEG    = 12'h302,
    CSR_MIDELEG    = 12'h303,
    CSR_MIE        = 12'h304,
    CSR_MTVEC      = 12'h305,
    CSR_MCOUNTEREN = 12'h306,
    CSR_MENVCFG    = 12'h30a,

    CSR_MSTATUSH = 12'h310,
    CSR_MENVCFGH = 12'h31a,

    CSR_MSCRATCH = 12'h340,
    CSR_MEPC     = 12'h341,
    CSR_MCAUSE   = 12'h342,
    CSR_MTVAL    = 12'h343,
    CSR_MIP      = 12'h344,

    CSR_MVENDORID = 12'hf11,
    CSR_MARCHID   = 12'hf12,
    CSR_MIMPID    = 12'hf13,
    CSR_MHARTID   = 12'hf14
  } csr_addr_e;

  typedef struct packed {
    logic [1:0] rw;        // [11:10] read/write class; 2'b11 is read-only
    priv_mode_t min_priv;  // [9:8] minimum privilege required by CSR address
    logic [7:0] index;     // [7:0] CSR index within the privilege/class space
  } csr_addr_fields_t;

  typedef union packed {
    csr_addr_raw_t    raw;     // full 12-bit CSR address
    csr_addr_e        named;   // known CSR address enum view
    csr_addr_fields_t fields;  // decoded CSR address fields
  } csr_addr_t;

  typedef logic [2:0] funct3_t;
  typedef logic [6:0] funct7_t;
  typedef logic [3:0] mem_write_mask_t;
  typedef word_t mtval_t;

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
  } alu_op_t;

  typedef enum logic [2:0] {
    MEM_BYTE  = 3'b000,  // LB / SB
    MEM_HALF  = 3'b001,  // LH / SH
    MEM_WORD  = 3'b010,  // LW / SW
    MEM_BYTEU = 3'b100,  // LBU
    MEM_HALFU = 3'b101   // LHU
  } mem_funct3_t;

  typedef enum logic [2:0] {
    SYS_F3_PRIV = 3'b000,  // ecall, ebreak, mret, wfi, etc.
    SYS_F3_RW   = 3'b001,  // csrrw
    SYS_F3_RS   = 3'b010,  // csrrs
    SYS_F3_RC   = 3'b011,  // csrrc
    SYS_F3_RWI  = 3'b101,  // csrrwi
    SYS_F3_RSI  = 3'b110,  // csrrsi
    SYS_F3_RCI  = 3'b111   // csrrci
  } sys_funct3_t;

  typedef enum logic [11:0] {
    SYS_IMM_ECALL  = 12'h000,
    SYS_IMM_EBREAK = 12'h001,
    SYS_IMM_WFI    = 12'h105,
    SYS_IMM_MRET   = 12'h302
  } sys_imm_t;

  typedef union packed {
    logic [11:0] raw;  // the bits, uninterpreted
    sys_imm_t    sys;  // SYSTEM privileged instruction immediate
  } imm12_u;

  typedef union packed {
    funct3_t     raw;  // the bits, uninterpreted
    alu_op_t     alu;  // OP, OP-IMM
    br_funct3_t  br;   // BRANCH
    mem_funct3_t mem;  // LOAD, STORE
    sys_funct3_t sys;  // SYSTEM
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
    imm12_u     imm;     // [31:20]
    logic [4:0] rs1;     // [19:15]
    funct3_u    funct3;  // [14:12]
    logic [4:0] rd;      // [11:7]
    opcode_t    opcode;  // [6:0]
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
  } imm_format_t;

  // Which pair of operands the ALU sees. Bit 1 selects SrcA (rs1 or PC), bit 0
  // selects SrcB (rs2 or the immediate); the names below spell out the pair.
  // PC + rs2 (2'b10) is never needed by any RV32I instruction.
  typedef enum logic [1:0] {
    ALU_OPERANDS_RS1_RS2 = 2'b00,  // R-type, and the branch comparison
    ALU_OPERANDS_RS1_IMM = 2'b01,  // I-type ALU, load/store address, jalr target
    ALU_OPERANDS_PC_IMM  = 2'b11   // branch/jal target, auipc
  } alu_operands_t;

  // First level of the writeback mux. These sources reach rd without touching
  // memory: the ALU's own output, the link address, the raw immediate, or the
  // old CSR value returned by a CSR instruction.
  typedef enum logic [1:0] {
    EXEC_RESULT_ALU      = 2'b00,  // R-type, I-type ALU, auipc (PC + imm)
    EXEC_RESULT_PC_PLUS4 = 2'b01,  // jal, jalr -- the return address
    EXEC_RESULT_IMM      = 2'b10,  // lui, which bypasses the ALU entirely
    EXEC_RESULT_CSR      = 2'b11   // CSR read result
  } execute_result_t;

  // Second level of the writeback mux: the value chosen above, or memory.
  typedef enum logic {
    WB_RESULT_EXEC = 1'b0,
    WB_RESULT_MEM  = 1'b1   // loads
  } writeback_result_t;

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

  typedef enum logic [1:0] {
    CSR_OP_RW,
    CSR_OP_RS,
    CSR_OP_RC
  } csr_op_t;

  typedef struct packed {
    logic    en;
    logic    write_en;
    csr_op_t op;
    logic    use_zimm;
  } csr_ctrl_t;

  typedef enum logic [2:0] {
    SYSTEM_OP_NONE,
    SYSTEM_OP_MRET,
    SYSTEM_OP_ECALL,
    SYSTEM_OP_EBREAK,
    SYSTEM_OP_WFI,
    SYSTEM_OP_ILLEGAL
  } system_op_t;

  typedef struct packed {
    logic       en;
    system_op_t op;
  } system_ctrl_t;

  // Decoded control-flow class. Branch and jump are mutually exclusive; the
  // branch condition itself is resolved later from funct3 and branch flags.
  typedef enum logic [1:0] {
    FLOW_NONE,
    FLOW_BRANCH,
    FLOW_JUMP
  } flow_t;

  typedef enum logic [3:0] {
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
    TRAP_SRC_MACHINE_EXTERNAL_INTERRUPT
  } trap_src_t;

  typedef struct packed {
    logic      valid;  // stage requests a synchronous trap
    trap_src_t src;    // trap source
    mtval_t    mtval;  // trap-specific value
  } trap_req_t;

  typedef struct packed {
    logic              reg_write_en;      // commit a value to integer register rd
    logic              mem_write_en;      // issue a store on the data bus
    imm_format_t       imm_format;        // instruction immediate encoding
    alu_op_t           alu_op;            // ALU function selected by decode
    alu_operands_t     alu_operands;      // values driven onto ALU src_a/src_b
    execute_result_t   execute_result;    // execute-stage value before memory
    writeback_result_t writeback_result;  // value committed to rd
    logic              sub_arith;         // use SUB/SRA variant for shared ALU op
    pc_src_t           pc_src;            // sequential PC or IEU-computed target
    logic              branch_sgnd;       // compare branch operands as signed
    mem_size_t         mem_size;          // byte/half/word memory transfer width
    logic              mem_unsigned;      // zero-extend load instead of sign-extend
    logic              clear_pc_lsb;      // force JALR target bit 0 to zero
    flow_t flow;                          // decoded branch/jump class
    trap_req_t         trap;              // decoded synchronous trap request
    csr_ctrl_t         csr;               // CSR read/write/set/clear control
    system_ctrl_t      system;            // privileged SYSTEM instruction control
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

  typedef mip_t mie_t;

  typedef enum logic [1:0] {
    MTVEC_MODE_DIRECT   = 2'b00,
    MTVEC_MODE_VECTORED = 2'b01
  } mtvec_mode_t;

  typedef struct packed {
    logic [29:0] base;  // [31:2] trap-vector base addres
    mtvec_mode_t mode;  // [1:0] trap-vector mode
  } mtvec_t;

  typedef pc_t mepc_t;

  typedef enum logic [30:0] {
    MCAUSE_INSTR_ADDR_MISALIGNED = 31'd0,
    MCAUSE_INSTR_ACCESS_FAULT    = 31'd1,
    MCAUSE_ILLEGAL_INSTR         = 31'd2,
    MCAUSE_BREAKPOINT            = 31'd3,
    MCAUSE_LOAD_ADDR_MISALIGNED  = 31'd4,
    MCAUSE_LOAD_ACCESS_FAULT     = 31'd5,
    MCAUSE_STORE_ADDR_MISALIGNED = 31'd6,
    MCAUSE_STORE_ACCESS_FAULT    = 31'd7,
    MCAUSE_ECALL_U               = 31'd8,
    MCAUSE_ECALL_S               = 31'd9,
    MCAUSE_ECALL_M               = 31'd11
  } exception_code_t;

  typedef struct packed {
    logic            is_interrupt;  // [31] 1 = interrupt, 0 = exception
    exception_code_t code;          // [30:0] exception/interrupt cause code
  } mcause_t;

  typedef csr_data_t mvendorid_t;
  typedef csr_data_t marchid_t;
  typedef csr_data_t mimpid_t;
  typedef csr_data_t mhartid_t;

  typedef struct packed {
    mepc_t   mepc;    // trapped instruction PC
    mcause_t mcause;  // trap cause
    mtval_t  mtval;   // trap-specific value
    pc_t     pc;      // trap vector target
  } trap_t;

  typedef struct packed {
    logic  valid;    // trap should be taken
    trap_t payload;  // architectural trap payload
  } trap_stage_t;

  typedef struct packed {
    mtvec_t     mtvec;
    mstatus_t   mstatus;
    mie_t       mie;
    mip_t       mip;
    mepc_t      mepc;
    priv_mode_t priv_mode;
  } csr_status_t;


endpackage
