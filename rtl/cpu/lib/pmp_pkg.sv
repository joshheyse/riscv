package pmp_pkg;
  import riscv_pkg::*;

  function automatic pmp_cfg_t legal_pmp_cfg(input logic [7:0] raw);
    pmp_cfg_t cfg;

    cfg = pmp_cfg_t'(raw);
    cfg.reserved = '0;
    if (cfg.write && !cfg.read) begin
      cfg.write = 1'b0;
    end
    return cfg;
  endfunction

  function automatic logic pmp_access_allowed(
      input pmp_state_t state, input mem_addr_t addr, input mem_size_e size,
      input mmu_access_e access, input priv_mode_e privilege);
    logic              matched;
    logic              allowed;
    logic       [34:0] access_start;
    logic       [34:0] access_end;

    matched = 1'b0;
    allowed = privilege == PRIV_MACHINE;
    access_start = {3'b000, addr};
    access_end = access_start + (35'(1) << int'(size));

    for (int unsigned entry = 0; entry < PmpNumEntries; entry++) begin
      logic       [34:0] region_start;
      logic       [34:0] region_end;
      logic       [34:0] napot_mask;
      int unsigned       trailing_ones;

      region_start = '0;
      region_end = '0;
      napot_mask = '0;
      trailing_ones = 0;

      case (state.cfg[entry].addr_match)
        PMP_ADDR_TOR: begin
          region_start = (entry == 0) ? '0 : ({3'b000, state.addr[entry-1]} << 2);
          region_end = {3'b000, state.addr[entry]} << 2;
        end
        PMP_ADDR_NA4: begin
          region_start = {3'b000, state.addr[entry]} << 2;
          region_end = region_start + 35'd4;
        end
        PMP_ADDR_NAPOT: begin
          for (int unsigned bit_index = 0; bit_index < 32; bit_index++) begin
            if ((trailing_ones == bit_index) && state.addr[entry][bit_index]) begin
              trailing_ones++;
            end
          end
          if (trailing_ones >= 31) begin
            region_start = '0;
            region_end = 35'(1) << 34;
          end else begin
            napot_mask = (35'(1) << (trailing_ones + 3)) - 1'b1;
            region_start = ({3'b000, state.addr[entry]} << 2) & ~napot_mask;
            region_end = region_start + (35'(1) << (trailing_ones + 3));
          end
        end
        default: begin
        end
      endcase

      if (!matched && (state.cfg[entry].addr_match != PMP_ADDR_OFF) &&
          (access_start < region_end) && (access_end > region_start)) begin
        matched = 1'b1;
        if ((access_start >= region_start) && (access_end <= region_end)) begin
          if ((privilege == PRIV_MACHINE) && !state.cfg[entry].locked) begin
            allowed = 1'b1;
          end else begin
            case (access)
              MMU_ACCESS_FETCH: allowed = state.cfg[entry].execute;
              MMU_ACCESS_LOAD:  allowed = state.cfg[entry].read;
              MMU_ACCESS_STORE: allowed = state.cfg[entry].write;
              default:          allowed = 1'b0;
            endcase
          end
        end else begin
          allowed = 1'b0;
        end
      end
    end

    return allowed;
  endfunction

endpackage
