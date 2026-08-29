`timescale 1ns / 1ps

module tlb_store
  import riscv_pkg::*;
#(
  parameter int unsigned TlbNumEntries = 16
) (
  input logic           clk,
  input logic           rst,
  input tlb_flush_req_t flush,

  input logic        we,
  input sv32_vpn_t   vpn,
  input sv32_asid_t  asid,
  input sv32_level_e write_level,
  input sv32_pte_t   write_pte,

  output logic        hit,
  output sv32_level_e read_level,
  output sv32_pte_t   read_pte
);

  localparam int unsigned TlbIndexBits = index_width(TlbNumEntries);
  typedef logic [TlbIndexBits-1:0] tlb_index_t;
  localparam tlb_index_t LastEntryIndex = tlb_index_t'(TlbNumEntries - 1);

  typedef struct packed {
    sv32_vpn_t   vpn;
    sv32_asid_t  asid;
    sv32_level_e level;
    sv32_pte_t   leaf_pte;
  } tlb_entry_t;

  tlb_entry_t                     _entries     [TlbNumEntries];
  logic       [TlbNumEntries-1:0] _valid;
  tlb_index_t                     _next_victim;
  tlb_index_t                     _write_index;

  always_comb begin
    logic found_invalid;
    _write_index  = _next_victim;
    found_invalid = 1'b0;
    for (int unsigned i = 0; i < TlbNumEntries; i++) begin
      if (!found_invalid && !_valid[i]) begin
        _write_index  = tlb_index_t'(i);
        found_invalid = 1'b1;
      end
    end
  end

  always_comb begin
    hit = '0;
    read_level = SV32_LEVEL_0;
    read_pte = '0;
    for (int unsigned i = 0; i < TlbNumEntries; i++) begin
      if (!flush.valid && !hit && _valid[i] &&
          (((_entries[i].level == SV32_LEVEL_1) &&
            (_entries[i].vpn.vpn1 == vpn.vpn1)) ||
           ((_entries[i].level == SV32_LEVEL_0) && (_entries[i].vpn == vpn))) &&
          (_entries[i].leaf_pte.global_mapping || (_entries[i].asid == asid))) begin
        hit = '1;
        read_level = _entries[i].level;
        read_pte = _entries[i].leaf_pte;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _valid <= '0;
      _next_victim <= '0;
    end else begin
      if (flush.valid) begin
        for (int unsigned i = 0; i < TlbNumEntries; i++) begin
          if (_valid[i] &&
              (flush.all_vpns ||
               ((_entries[i].level == SV32_LEVEL_1) &&
                (_entries[i].vpn.vpn1 == flush.vpn.vpn1)) ||
               ((_entries[i].level == SV32_LEVEL_0) && (_entries[i].vpn == flush.vpn))) &&
              (flush.all_asids ||
               (!_entries[i].leaf_pte.global_mapping && (_entries[i].asid == flush.asid)))) begin
            _valid[i] <= 1'b0;
          end
        end
        if (flush.all_vpns && flush.all_asids) begin
          _next_victim <= '0;
        end
      end else if (we) begin
        _entries[_write_index] <= '{
            vpn: vpn,
            asid: asid,
            level: write_level,
            leaf_pte: write_pte
        };
        _valid[_write_index] <= 1'b1;
        _next_victim <= (_write_index == LastEntryIndex) ? '0 : _write_index + 1;
      end
    end
  end

endmodule
