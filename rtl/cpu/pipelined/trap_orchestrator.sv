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
  input logic        clk,
  input logic        rst,

  input trap_stage_t id_trap,
  input trap_stage_t ex_trap,
  input trap_stage_t mem_trap,

  input logic        clear_trap,

  output trap_stage_t trap,
  output logic       trap_in_flight
);

  logic        _trap_held;
  trap_stage_t _candidate;
  trap_stage_t _held_trap;

  always_comb begin
    if (mem_trap.valid) begin
      _candidate = mem_trap;
    end else if (ex_trap.valid) begin
      _candidate = ex_trap;
    end else begin
      _candidate = id_trap;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _held_trap <= '0;
    end else if (clear_trap) begin
      _held_trap <= '0;
    end else if (!_trap_held && _candidate.valid) begin
      _held_trap <= _candidate;
    end
  end

  always_comb begin
    trap = _trap_held ? _held_trap : _candidate;
    trap_in_flight = _candidate.valid || _trap_held;
  end

  assign _trap_held = _held_trap.valid;

endmodule
