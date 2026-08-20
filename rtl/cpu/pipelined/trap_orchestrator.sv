`timescale 1ns / 1ps

// Selects and holds the oldest pending trap until retirement.
//
// Priority is architectural age within the pipeline: MEM/WB stage first,
// then EX/MEM, then ID/EX. The selected trap is held in-flight across
// multiple cycles until clear_trap is asserted, preventing younger traps from
// replacing older pending work.
module trap_orchestrator
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst,

  input trap_stage_t id_trap,
  input trap_stage_t ex_trap,
  input trap_stage_t mem_trap,

  input logic clear_trap,

  output trap_stage_t trap,
  output logic        trap_held,
  output logic        trap_in_flight,
  // Whether the in-flight trap belongs to the instruction still sitting in
  // decode. The pipeline needs this to know that instruction must advance
  // rather than be flushed, and it has to stay true for as long as the trap is
  // held: a trap can be latched during a memory wait, cycles before the
  // pipeline is allowed to move it.
  output logic        trap_from_id
);

  logic        _trap_held;
  trap_stage_t _candidate;
  trap_stage_t _held_trap;
  logic        _candidate_from_id;
  logic        _held_from_id;

  always_comb begin
    _candidate_from_id = 1'b0;
    if (mem_trap.valid) begin
      _candidate = mem_trap;
    end else if (ex_trap.valid) begin
      _candidate = ex_trap;
    end else begin
      _candidate = id_trap;
      _candidate_from_id = id_trap.valid;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _held_trap <= '0;
      _held_from_id <= 1'b0;
    end else if (clear_trap) begin
      _held_trap <= '0;
      _held_from_id <= 1'b0;
    end else if (!_trap_held && _candidate.valid) begin
      _held_trap <= _candidate;
      _held_from_id <= _candidate_from_id;
    end
  end

  always_comb begin
    trap = _trap_held ? _held_trap : _candidate;
    trap_in_flight = _candidate.valid || _trap_held;
    trap_from_id = _trap_held ? _held_from_id : _candidate_from_id;
  end

  assign trap_held  = _held_trap.valid;
  assign _trap_held = trap_held;

endmodule
