`timescale 1ns / 1ps

module plic
  import riscv_pkg::*;
#(

  parameter mem_addr_t   PlicBase               = 32'h0C000000,
  parameter mem_addr_t   PlicPriorityBaseAddr   = 32'h0C000000,
  parameter mem_addr_t   PlicPendingAddr        = 32'h0C001000,
  parameter mem_addr_t   PlicMEnableAddr        = 32'h0C002000,
  parameter mem_addr_t   PlicMThresholdAddr     = 32'h0C200000,
  parameter mem_addr_t   PlicMClaimCompleteAddr = 32'h0C200004,
  parameter int unsigned NumSources             = 3,
  parameter int unsigned PriorityBits           = 3
) (
  input logic clk,
  input logic rst,

  output logic selected,

  irq_if.sink   sources[NumSources:1],
  irq_if.source irq,

  mem_if.slave mem
);


  // This slave can always take a request on the cycle it is presented, so
  // acceptance is unconditional. Drive it for real only if that changes.
  assign mem.req_ready = 1'b1;

  localparam int unsigned WordBits = $bits(mem_data_t);
  localparam mem_addr_t PlicEndAddr = PlicMClaimCompleteAddr + mem_addr_t'(4);
  localparam mem_addr_t PriorityEndAddr = PlicPriorityBaseAddr + mem_addr_t'(4 * (NumSources + 1));

  localparam int unsigned SourceIdBits = $clog2(NumSources + 1);
  typedef logic [SourceIdBits-1:0] source_id_t;

  initial begin
    assert (NumSources > 0);
    assert (NumSources < WordBits);
    assert (PriorityBits > 0);
    assert (PriorityBits <= WordBits);
  end

  logic [NumSources:1] _source_pending;
  logic [NumSources:1] _pending;
  logic [NumSources:1] _source_en;

  typedef logic [PriorityBits-1:0] priority_t;
  priority_t  _priority          [NumSources:1];
  priority_t  _threshold;
  logic       _priority_selected;

  source_id_t _source_id;

  source_id_t _claim_id;
  priority_t  _claim_priority;
  logic       _claim_valid;
  logic       _winner_valid;

  source_id_t _complete_id;
  logic       _complete_valid;

  assign _source_id = source_id_t'((mem.req.addr - PlicPriorityBaseAddr) >> 2);

  assign selected = mem.req.valid && (mem.req.addr >= PlicBase && mem.req.addr < PlicEndAddr);
  assign _priority_selected = (mem.req.addr >= PlicPriorityBaseAddr) && (mem.req.addr < PriorityEndAddr) && (mem.req.addr[1:0] == 2'b00);

  for (genvar id = 1; id <= NumSources; id++) begin : gen_source_pending
    assign _source_pending[id] = sources[id].pending.meip;

    plic_gateway _gateway (
      .clk(clk),
      .rst(rst),
      .request(_source_pending[id]),
      .claim(_claim_valid && (_claim_id == id)),
      .complete(_complete_valid && (_complete_id == id)),
      .pending(_pending[id])
    );

  end

  always_comb begin
    _claim_id = '0;
    _claim_priority = '0;
    _winner_valid = 1'b0;
    _claim_valid = 1'b0;
    _complete_id = '0;
    _complete_valid = 1'b0;

    for (int unsigned id = 1; id <= NumSources; id++) begin : gen_claim
      if (_pending[id] && _source_en[id] && (_priority[id] > _threshold)) begin
        if (_claim_priority < _priority[id]) begin
          _claim_id = source_id_t'(id);
          _claim_priority = _priority[id];
          _winner_valid = 1'b1;
        end
      end
    end

    irq.pending.meip = _winner_valid;

    mem.rsp.read_data = '0;
    mem.rsp.valid = selected;
    if (mem.req.valid) begin
      if (_priority_selected && (_source_id != '0)) begin
        mem.rsp.read_data = {{(WordBits - PriorityBits) {1'b0}}, _priority[_source_id]};
      end else if (mem.req.addr == PlicPendingAddr) begin
        mem.rsp.read_data = {{(WordBits - NumSources - 1) {1'b0}}, _pending, 1'b0};
      end else if (mem.req.addr == PlicMEnableAddr) begin
        mem.rsp.read_data = {{(WordBits - NumSources - 1) {1'b0}}, _source_en, 1'b0};
      end else if (mem.req.addr == PlicMThresholdAddr) begin
        mem.rsp.read_data = {{(WordBits - PriorityBits) {1'b0}}, _threshold};
      end else if (mem.req.addr == PlicMClaimCompleteAddr && !mem.req.write_en) begin
        mem.rsp.read_data = {{(WordBits - SourceIdBits) {1'b0}}, _claim_id};
        _claim_valid = _winner_valid;
      end else if (mem.req.addr == PlicMClaimCompleteAddr && mem.req.write_en &&
                   mem.req.write_data >= mem_data_t'(1) &&
                   mem.req.write_data <= mem_data_t'(NumSources)) begin
        _complete_id = source_id_t'(mem.req.write_data);
        _complete_valid = 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _source_en <= '0;
      _threshold <= '0;
      for (int unsigned id = 1; id <= NumSources; id++) begin
        _priority[id] <= '0;
      end
    end else begin
      if (mem.req.valid && mem.req.write_en) begin
        if (_priority_selected && (_source_id != '0)) begin
          _priority[_source_id] <= priority_t'(mem.req.write_data);
        end else if (mem.req.addr == PlicMEnableAddr) begin
          _source_en <= mem.req.write_data[NumSources:1];
        end else if (mem.req.addr == PlicMThresholdAddr) begin
          _threshold <= priority_t'(mem.req.write_data);
        end
      end
    end
  end

endmodule
