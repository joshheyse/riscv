`timescale 1ns / 1ps

module mmio_router
  import riscv_pkg::*;
#(
  parameter int unsigned NumSources = 1,
  parameter int unsigned DmemIdx = 0,  // index of DMem source
  parameter bit DmemHasPrio = 1'b1,  // DMem loses to any MMIO hit
  parameter mmio_source_t SourceMap[NumSources] = '{
      default: '{start_addr: '0, end_addr: '0, writeable: 1'b0}
  }
) (
  input  mem_if.slave                   dbus,
  output logic         [NumSources-1:0] selected,
         mem_if.master                  mem     [NumSources]
);

  localparam int unsigned WordBits = $bits(mem_data_t);
  logic        [NumSources-1:0] _selected;
  logic        [NumSources-1:0] _source_ready;
  logic        [  WordBits-1:0] _source_read_data[NumSources];
  logic        [NumSources-1:0] _dmem_mask;

  int unsigned                  _i;
  logic                         _mmio_selected;

  always_comb begin
    _dmem_mask = '0;
    if (DmemIdx < NumSources) begin
      _dmem_mask[DmemIdx] = 1'b1;
    end

    _selected = '0;
    for (_i = 0; _i < NumSources; _i++) begin
      if ((dbus.req.addr >= SourceMap[_i].start_addr) && (dbus.req.addr < SourceMap[_i].end_addr)) begin
        _selected[_i] = 1'b1;
      end
    end

    _mmio_selected = |(_selected & ~_dmem_mask);

    if (DmemHasPrio && (DmemIdx < NumSources)) begin
      _selected[DmemIdx] = _selected[DmemIdx] & ~_mmio_selected;
    end
  end

  // Safety: should only ever be at most one selected
  always_comb begin
    assert ($onehot0(_selected));
    selected = _selected;
  end

  // Route request into each source interface
  //
  generate
    for (genvar gi = 0; gi < NumSources; gi++) begin : GEN_MEM_REQUEST
      assign mem[gi].req = '{
              valid    : dbus.req.valid && _selected[gi],
              write_en : dbus.req.write_en && _selected[gi] && SourceMap[gi].writeable,
              addr     : dbus.req.addr,
              write_data: dbus.req.write_data,
              write_mask: dbus.req.write_mask
          };
    end
  endgenerate

  generate
    for (genvar g = 0; g < NumSources; g++) begin : GEN_MEM_BACKPRESSURE
      assign _source_ready[g]     = mem[g].rsp.ready;
      assign _source_read_data[g] = mem[g].rsp.read_data;
    end
  endgenerate

  onehot_mux #(
    .Width(WordBits),
    .NumInputs(NumSources)
  ) _read_mux (
    .selected(_selected),
    .data_in(_source_read_data),
    .data_out(dbus.rsp.read_data)
  );

  always_comb begin
    if (|_selected) begin
      dbus.rsp.ready = |(_selected & _source_ready);
    end else begin
      dbus.rsp.ready = dbus.req.valid;
    end
  end
endmodule
