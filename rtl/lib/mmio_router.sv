`timescale 1ns / 1ps

module mmio_router
  import riscv_pkg::*;
#(
  parameter int unsigned NumSources = 1,
  parameter int unsigned MemIdx = 0,  // index of default memory source
  parameter bit MemHasPrio = 1'b1,  // default memory loses to any MMIO hit
  parameter mmio_source_t SourceMap[NumSources] = '{
      default: '{start_addr: '0, end_addr: '0, writeable: 1'b0}
  }
) (
  input  logic                          clk,
  input  logic                          rst,
  input  mem_if.slave                   dbus,
  output logic         [NumSources-1:0] selected,
         mem_if.master                  mem     [NumSources]
);

  localparam int unsigned WordBits = $bits(mem_data_t);
  logic        [NumSources-1:0] _selected;
  logic        [NumSources-1:0] _owner;
  logic        [NumSources-1:0] _route;
  logic        [NumSources-1:0] _source_ready;
  logic        [NumSources-1:0] _source_req_ready;
  logic        [  WordBits-1:0] _source_read_data [NumSources];
  logic        [NumSources-1:0] _mem_mask;

  int unsigned                  _i;
  logic                         _mmio_selected;
  logic                         _outstanding;
  logic                         _accept;
  logic                         _unmapped;
  logic                         _answered_now;

  always_comb begin
    _mem_mask = '0;
    if (MemIdx < NumSources) begin
      _mem_mask[MemIdx] = 1'b1;
    end

    _selected = '0;
    for (_i = 0; _i < NumSources; _i++) begin
      if ((dbus.req.addr >= SourceMap[_i].start_addr) && (dbus.req.addr < SourceMap[_i].end_addr)) begin
        _selected[_i] = 1'b1;
      end
    end

    _mmio_selected = |(_selected & ~_mem_mask);

    if (MemHasPrio && (MemIdx < NumSources)) begin
      _selected[MemIdx] = _selected[MemIdx] & ~_mmio_selected;
    end
  end

  // Safety: should only ever be at most one selected
  always_comb begin
    assert ($onehot0(_selected));
    selected = _selected;
  end

  // Which source owns the response. The selection is decoded from the request
  // address, but a master releases its request as soon as the router accepts
  // it -- so the target has to be latched for the rest of the transaction or
  // the response would be routed by a stale address.
  assign _unmapped = ~|_selected;
  assign _accept = dbus.req.valid && dbus.req_ready;
  assign _route = _outstanding ? _owner : _selected;
  assign _answered_now = |(_selected & _source_ready);
  assign dbus.req_ready = !_outstanding && (_unmapped || |(_selected & _source_req_ready));

  always_ff @(posedge clk) begin
    if (rst) begin
      _outstanding <= 1'b0;
      _owner <= '0;
    end else if (_outstanding) begin
      if (|(_owner & _source_ready) && dbus.rsp_ready) begin
        _outstanding <= 1'b0;
      end
    end else if (_accept && !(_unmapped && dbus.rsp_ready)
                 && !(_answered_now && dbus.rsp_ready)) begin
      _outstanding <= 1'b1;
      _owner <= _selected;
    end
  end

  // Route request into each source interface
  //
  generate
    for (genvar gi = 0; gi < NumSources; gi++) begin : GEN_MEM_REQUEST
      assign mem[gi].req = '{
              valid    : dbus.req.valid && _selected[gi] && !_outstanding,
              write_en : dbus.req.write_en && _selected[gi] && SourceMap[gi].writeable,
              addr     : dbus.req.addr,
              write_data: dbus.req.write_data,
              write_mask: dbus.req.write_mask
          };
    end
  endgenerate

  generate
    for (genvar g = 0; g < NumSources; g++) begin : GEN_MEM_BACKPRESSURE
      assign _source_ready[g]     = mem[g].rsp.valid;
      assign _source_req_ready[g] = mem[g].req_ready;
      assign _source_read_data[g] = mem[g].rsp.read_data;
      // Only the source that owns the transaction is told the response was
      // taken; the rest must not see an acceptance meant for someone else.
      assign mem[g].rsp_ready     = dbus.rsp_ready && _route[g];
    end
  endgenerate

  onehot_mux #(
    .Width(WordBits),
    .NumInputs(NumSources)
  ) _read_mux (
    .selected(_route),
    .data_in(_source_read_data),
    .data_out(dbus.rsp.read_data)
  );

  always_comb begin
    if (_outstanding) begin
      dbus.rsp.valid = |(_owner & _source_ready);
    end else if (|_selected) begin
      dbus.rsp.valid = _answered_now;
    end else begin
      // An unmapped access is answered here, in the cycle it is accepted.
      dbus.rsp.valid = dbus.req.valid;
    end
  end
endmodule
