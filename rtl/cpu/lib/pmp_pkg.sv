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

  /* verilator lint_off UNUSEDSIGNAL */
  function automatic pmp_region_t pmp_decode_region(
      input pmp_addr_t addr, input pmp_addr_t predecessor_addr, input pmp_cfg_t cfg);
    pmp_region_t region;
    logic [34:0] encoded_addr;
    logic [34:0] napot_mask;

    region = '0;
    region.valid = cfg.addr_match != PMP_ADDR_OFF;
    region.locked = cfg.locked;
    region.execute = cfg.execute;
    region.write = cfg.write;
    region.read = cfg.read;
    encoded_addr = {3'b000, addr};
    napot_mask = '0;

    case (cfg.addr_match)
      PMP_ADDR_TOR: begin
        region.start = {3'b000, predecessor_addr} << 2;
        region.end_addr = encoded_addr << 2;
      end
      PMP_ADDR_NA4: begin
        region.start = encoded_addr << 2;
        region.end_addr = region.start + 35'd4;
      end
      PMP_ADDR_NAPOT: begin
        // A NAPOT entry encodes a run of low one bits. For runs shorter than
        // 31, x ^ (x + 1) produces the run plus its terminating zero, and
        // shifting into byte-address space supplies the two low address bits.
        if (addr[30:0] == 31'h7fff_ffff) begin
          region.start = '0;
          region.end_addr = 35'(1) << 34;
        end else begin
          napot_mask = ((encoded_addr ^ (encoded_addr + 35'd1)) << 2) | 35'd3;
          region.start = (encoded_addr << 2) & ~napot_mask;
          region.end_addr = region.start + napot_mask + 35'd1;
        end
      end
      default: begin
      end
    endcase

    return region;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  function automatic pmp_region_state_t pmp_decode_regions(input pmp_state_t state);
    pmp_region_state_t regions;

    regions = '0;
    for (int unsigned entry = 0; entry < PmpNumEntries; entry++) begin
      regions.entries[entry] = pmp_decode_region(
          state.addr[entry],
          (entry == 0) ? '0 : state.addr[entry-1],
          state.cfg[entry]);
    end
    return regions;
  endfunction

  function automatic pmp_state_t pmp_state_after_write(
      input pmp_state_t state, input csr_addr_raw_t addr, input csr_data_t write_data);
    pmp_state_t next_state;

    next_state = state;
    case (addr)
      CSR_PMPCFG0, CSR_PMPCFG1, CSR_PMPCFG2, CSR_PMPCFG3: begin
        for (int unsigned lane = 0; lane < 4; lane++) begin
          int unsigned entry;
          entry = ((int'(addr) - int'(CSR_PMPCFG0)) * 4) + lane;
          if (!state.cfg[entry].locked) begin
            next_state.cfg[entry] = legal_pmp_cfg(write_data[(lane*8)+:8]);
          end
        end
      end
      CSR_PMPADDR0, CSR_PMPADDR1, CSR_PMPADDR2, CSR_PMPADDR3,
          CSR_PMPADDR4, CSR_PMPADDR5, CSR_PMPADDR6, CSR_PMPADDR7,
          CSR_PMPADDR8, CSR_PMPADDR9, CSR_PMPADDR10, CSR_PMPADDR11,
          CSR_PMPADDR12, CSR_PMPADDR13, CSR_PMPADDR14, CSR_PMPADDR15: begin
        int unsigned entry;
        logic predecessor_locked;

        entry = int'(addr) - int'(CSR_PMPADDR0);
        predecessor_locked = (entry < (PmpNumEntries - 1)) &&
            state.cfg[entry+1].locked && (state.cfg[entry+1].addr_match == PMP_ADDR_TOR);
        if (!state.cfg[entry].locked && !predecessor_locked) begin
          next_state.addr[entry] = write_data;
        end
      end
      default: begin
      end
    endcase
    return next_state;
  endfunction

  function automatic logic pmp_access_allowed(
      input pmp_region_state_t state, input mem_addr_t addr, input mem_size_e size,
      input mmu_access_e access, input priv_mode_e privilege);
    logic              matched;
    logic              allowed;
    logic       [34:0] access_start;
    logic       [34:0] access_end;
    logic       [34:0] access_bytes;

    matched = 1'b0;
    allowed = privilege == PRIV_MACHINE;
    access_start = {3'b000, addr};
    case (size)
      MEM_SIZE_BYTE: access_bytes = 35'd1;
      MEM_SIZE_HALF: access_bytes = 35'd2;
      MEM_SIZE_WORD: access_bytes = 35'd4;
      default:       access_bytes = 35'd8;
    endcase
    access_end = access_start + access_bytes;

    for (int unsigned entry = 0; entry < PmpNumEntries; entry++) begin
      if (!matched && state.entries[entry].valid &&
          (access_start < state.entries[entry].end_addr) &&
          (access_end > state.entries[entry].start)) begin
        matched = 1'b1;
        if ((access_start >= state.entries[entry].start) &&
            (access_end <= state.entries[entry].end_addr)) begin
          if ((privilege == PRIV_MACHINE) && !state.entries[entry].locked) begin
            allowed = 1'b1;
          end else begin
            case (access)
              MMU_ACCESS_FETCH: allowed = state.entries[entry].execute;
              MMU_ACCESS_LOAD:  allowed = state.entries[entry].read;
              MMU_ACCESS_STORE: allowed = state.entries[entry].write;
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
