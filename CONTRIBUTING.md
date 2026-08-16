# Contributing

This project is a learning RV32I SoC. Keep changes small, explicit, and easy
to inspect. RTL implementation choices belong to Josh; build tooling,
testbenches, and mechanical cleanup can be updated as needed.

## SystemVerilog Style

### Ports

Module boundary names are public names. Do not give ports or interface ports a
leading underscore.

Order ports by direction/role:

1. `input`
2. `output`
3. `inout`
4. interface/modport ports

Align declarations locally within the port block:

```systemverilog
module example
  import riscv_pkg::*;
(
  input  logic      clk,
  input  logic      rst,
  input  word_t     addr,
  input  mem_size_t size,

  output logic      ready,
  output word_t     read_data,

  mem_if.master mem
);
```

### Internal Names

Everything local to a module gets a leading `_`. This includes helper signals,
registered state, local interface instances, and submodule instances.

```systemverilog
logic          _load_instr;
logic          _load_complete;
word_t         _alu_result;
branch_flags_t _branch_flags;

mem_if _mem();

alu        _alu (...);
controller _controller (...);
```

Registered state may use `_q` for the flip-flop output and `_d` for the next
value, matching the D and Q pins of a flip-flop:

```systemverilog
logic _valid_q;
logic _valid_d;

always_comb begin
  _valid_d = _valid_q;
  if (start) begin
    _valid_d = 1'b1;
  end
end

always_ff @(posedge clk) begin
  if (rst) begin
    _valid_q <= 1'b0;
  end else begin
    _valid_q <= _valid_d;
  end
end
```

Use `_n` for active-low signals. External active-low ports stay public:

```systemverilog
input logic rst_n;

logic _reset_n;
```

Use `_en` for enable signals. Public enable ports use `en` when the context is
already clear, or a descriptive `_en` suffix when it is not. Avoid spelling out
`enable` or using `_enabled` for signal names.

```systemverilog
input logic en;
input logic pc_en;
input logic mem_write_en;

logic _stg_en;
logic _write_en;
```

`oe` is allowed as the conventional hardware abbreviation for output enable
pins:

```systemverilog
output logic [NumGpio-1:0] gpio_oe;
```

Unused input accounting also uses the private-name convention:

```systemverilog
logic _unused_write_data;
assign _unused_write_data = |write_data[31:8];
```

### Constants And Types

Constants and local types are not private data signals, so they do not use the
leading underscore convention. Use descriptive CamelCase names for localparams.

```systemverilog
localparam int unsigned WordBits = $bits(addr);

typedef enum logic [1:0] {
  Idle,
  Busy
} state_t;
```

### Interfaces

Interface fields are already scoped by the interface instance, so avoid
redundant prefixes inside the interface itself.

```systemverilog
interface mem_if
  import riscv_pkg::*;
();

  typedef struct packed {
    logic            valid;
    logic            write_en;
    word_t           addr;
    word_t           write_data;
    mem_write_mask_t write_mask;
  } req_t;

  typedef struct packed {
    logic  ready;
    word_t read_data;
  } rsp_t;

  req_t req;
  rsp_t rsp;
endinterface
```

Usage at module boundaries remains clean:

```systemverilog
assign dbus.req.valid = _load_instr;
assign _stall = dbus.req.valid && !dbus.rsp.ready;
```

### Module Organization

Use this default shape for small modules:

```systemverilog
module example (...);

  localparam int unsigned WordBits = $bits(addr);

  logic  _selected;
  word_t _read_data;

  initial begin
    assert (WordBits == 32);
  end

  assign _selected = ...;
  assign read_data = _read_data;

  always_comb begin
    ...
  end

  always_ff @(posedge clk) begin
    ...
  end

  logic _unused;
  assign _unused = |addr[1:0];

endmodule
```

For larger integration modules, group related declarations, assigns, instances,
and unused-signal accounting by subsystem when that is clearer than grouping
strictly by statement type.

### Formatting

Run:

```sh
make fmt
make style
```

`make fmt` handles whitespace and local alignment. `make style` checks the
project-specific naming rules that generic tools do not know about.
