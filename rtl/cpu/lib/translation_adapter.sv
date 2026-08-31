`timescale 1ns / 1ps

module translation_adapter
  import riscv_pkg::*;
  import sv32_pkg::*;
#(
  parameter bit TlbEnabled = 1'b1
) (
  input logic           clk,
  input logic           rst,
  input tlb_flush_req_t tlb_flush,

  input satp_t            satp,
  input translation_ctx_t ctx,

  vmem_if.slave    upstream,
  mmu_if.requester translation,
  mem_if.master    downstream
);

  typedef enum logic [2:0] {
    IDLE,
    TRANSLATE_REQUEST,
    TRANSLATE_WAIT,
    PHYSICAL_REQUEST,
    PHYSICAL_WAIT,
    RESPOND
  } state_e;

  state_e           _state;
  translation_ctx_t _ctx;
  sv32_asid_t       _request_asid;
  mmu_req_t         _mmu_request;
  // verilator lint_off UNUSEDSIGNAL
  vmem_req_t        _vmem_request;
  // verilator lint_on UNUSEDSIGNAL
  vmem_rsp_t        _vmem_response;
  mem_addr_t        _physical_addr;
  mem_req_t         _mem_request;

  always_comb begin
    upstream.rsp = _vmem_response;
    // Always take an IDLE request into the adapter.  In Bare mode the old
    // implementation forwarded downstream.req_ready combinationally here;
    // buffering the request keeps the physical ready network out of the
    // pipeline's memory-wait path.
    upstream.req_ready = (_state == IDLE);
    translation.req = _mmu_request;
    translation.rsp_ready = (_state == TRANSLATE_WAIT);
    downstream.req = _mem_request;
    // A physical slave may return a response in the request-acceptance cycle.
    // It is safe to accept that response only when the registered request is
    // being accepted on this edge; otherwise wait for PHYSICAL_WAIT.
    downstream.rsp_ready = (_state == PHYSICAL_WAIT) ||
        ((_state == PHYSICAL_REQUEST) && _mem_request.valid && downstream.req_ready);
  end

  logic             _tlb_we;
  logic             _tlb_epoch;
  logic             _request_tlb_epoch;
  virtual_address_u _tlb_virtual_addr;
  sv32_vpn_t        _tlb_vpn;
  sv32_asid_t       _tlb_asid;
  sv32_level_e      _tlb_write_level;
  sv32_pte_t        _tlb_write_pte;
  logic             _tlb_hit;
  sv32_level_e      _tlb_read_level;
  sv32_pte_t        _tlb_read_pte;
  mmu_req_t         _tlb_request;
  logic             _tlb_access_allowed;
  mem_addr_t        _tlb_physical_addr;

  tlb_store _tlb (
    .clk(clk),
    .rst(rst),
    .flush(tlb_flush),
    .we(_tlb_we),
    .vpn(_tlb_vpn),
    .asid(_tlb_asid),
    .write_level(_tlb_write_level),
    .write_pte(_tlb_write_pte),
    .hit(_tlb_hit),
    .read_level(_tlb_read_level),
    .read_pte(_tlb_read_pte)
  );

  always_comb begin
    _tlb_virtual_addr = (_state == IDLE) ? virtual_address_u'(upstream.req.addr) :
                                          virtual_address_u'(_vmem_request.addr);
    _tlb_we = 1'b0;
    _tlb_vpn = _tlb_virtual_addr.fields.vpn;
    _tlb_asid = (_state == IDLE) ? satp.asid : _request_asid;
    _tlb_write_level = translation.rsp.leaf_level;
    _tlb_write_pte = translation.rsp.leaf_pte;

    if (TlbEnabled && (_state == TRANSLATE_WAIT) && translation.rsp.valid && translation.rsp_ready &&
        (translation.rsp.fault == MMU_FAULT_NONE) && !tlb_flush.valid &&
        (_request_tlb_epoch == _tlb_epoch)) begin
      _tlb_we = 1'b1;
    end
  end

  always_comb begin
    _tlb_request = '{valid: upstream.req.valid, virtual_addr: _tlb_virtual_addr, ctx: ctx};
    _tlb_access_allowed = leaf_access_allowed(_tlb_read_pte, _tlb_request);
    _tlb_physical_addr = leaf_physical_address(_tlb_read_pte, _tlb_read_level, _tlb_virtual_addr);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _state <= IDLE;
      _tlb_epoch <= 1'b0;
      _ctx <= '0;
      _mmu_request <= '0;
      _vmem_request <= '0;
      _vmem_response <= '0;
      _physical_addr <= '0;
      _mem_request <= '0;
    end else begin
      if (tlb_flush.valid) begin
        _tlb_epoch <= ~_tlb_epoch;
      end
      case (_state)
        IDLE: begin
          if (upstream.req.valid && upstream.req_ready) begin
            if (translation_bypassed(satp, ctx)) begin
              _physical_addr <= upstream.req.addr;
              _ctx <= ctx;
              _vmem_request <= upstream.req;
              // Construct the downstream request in PHYSICAL_REQUEST after
              // the physical-address PMP check. No downstream ready signal is
              // part of the IDLE acceptance decision.
              _mem_request <= '0;
              _state <= PHYSICAL_REQUEST;
            end else begin
              _ctx <= ctx;
              _vmem_request <= upstream.req;
              if (TlbEnabled && _tlb_hit) begin
                if (_tlb_access_allowed) begin
                  _physical_addr <= _tlb_physical_addr;
                  _state <= PHYSICAL_REQUEST;
                end else begin
                  _vmem_response <= '{
                      valid: 1'b1,
                      fault: MMU_FAULT_PAGE,
                      read_data: '0,
                      physical_addr: '0
                  };
                  _state <= RESPOND;
                end
              end else begin
                _state <= TRANSLATE_REQUEST;
              end
            end
          end
        end
        TRANSLATE_REQUEST: begin
          _mmu_request <= '{valid: 1'b1, virtual_addr: _vmem_request.addr, ctx: _ctx};
          if (translation.req.valid && translation.req_ready) begin
            _mmu_request <= '0;
            _state <= TRANSLATE_WAIT;
          end
        end
        TRANSLATE_WAIT: begin
          if (translation.rsp.valid) begin
            if (translation.rsp.fault != MMU_FAULT_NONE) begin
              _vmem_response <= '{
                  valid: 1'b1,
                  fault: translation.rsp.fault,
                  read_data: '0,
                  physical_addr: '0
              };
              _state <= RESPOND;
            end else begin
              _physical_addr <= translation.rsp.physical_addr;
              _state <= PHYSICAL_REQUEST;
            end
          end
        end
        PHYSICAL_REQUEST: begin
          _mem_request <= '{
              valid: 1'b1,
              addr: _physical_addr,
              size: _vmem_request.size,
              access: _ctx.access,
              privilege: _ctx.privilege,
              write_en: _vmem_request.write_en,
              write_data: _vmem_request.write_data,
              write_mask: _vmem_request.write_mask
          };
          if (downstream.req.valid && downstream.req_ready) begin
            _mem_request.valid <= 1'b0;
            if (downstream.rsp.valid) begin
              _vmem_response <= '{
                  valid: 1'b1,
                  fault: downstream.rsp.fault,
                  read_data: downstream.rsp.read_data,
                  physical_addr: downstream.rsp.fault == MMU_FAULT_NONE ?
                      _physical_addr : '0
              };
              _state <= RESPOND;
            end else begin
              _state <= PHYSICAL_WAIT;
            end
          end
        end
        PHYSICAL_WAIT: begin
          if (downstream.rsp.valid) begin
            _vmem_response <= '{
                valid: 1'b1,
                fault: downstream.rsp.fault,
                read_data: downstream.rsp.read_data,
                physical_addr: downstream.rsp.fault == MMU_FAULT_NONE ?
                    _physical_addr : '0
            };
            _state <= RESPOND;
          end
        end
        RESPOND: begin
          if (_vmem_response.valid && upstream.rsp_ready) begin
            _vmem_response.valid <= 1'b0;
            _state <= IDLE;
          end
        end
        default: begin
        end
      endcase
    end

  end

  // ASID and epoch are needed only to validate a walker result before filling
  // the TLB.  A hit never consumes them, so keep their capture off the hit
  // response/control cone and sample them only for a real translation miss.
  always_ff @(posedge clk) begin
    if (rst) begin
      _request_asid <= '0;
      _request_tlb_epoch <= 1'b0;
    end else if ((_state == IDLE) && upstream.req.valid && upstream.req_ready &&
                 TlbEnabled && !translation_bypassed(satp, ctx) && !_tlb_hit) begin
      _request_asid <= satp.asid;
      _request_tlb_epoch <= _tlb_epoch;
    end
  end

endmodule
