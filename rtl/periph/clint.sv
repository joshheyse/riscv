`timescale 1ns / 1ps

// Minimal CLINT-like block for machine-level timer/software interrupts.
//
// It models three software-visible features:
//   - MSIP: software interrupt pending bit at `MsipAddr`
//   - mtimecmp: 64-bit compare value split into lo/hi registers
//   - mtime: free-running 64-bit timer
//
// The block raises `irq.pending.msip` from MSIP and `irq.pending.mtip`
// when `mtime >= mtimecmp`.
module clint
  import riscv_pkg::*;
#(
  parameter mem_addr_t MsipAddr       = 32'h10002008,
  parameter mem_addr_t MtimecmpLoAddr = 32'h10002010,
  parameter mem_addr_t MtimecmpHiAddr = 32'h10002014,
  parameter mem_addr_t MtimeLoAddr    = 32'h10002018,
  parameter mem_addr_t MtimeHiAddr    = 32'h1000201C
) (
  input  logic         clk,
  input  logic         rst,
  output logic         selected,
  output irq_if.source irq,

  mem_if.slave mem
);

  initial begin
    assert (MsipAddr != MtimecmpLoAddr);
    assert (MsipAddr != MtimecmpHiAddr);
    assert (MsipAddr != MtimeLoAddr);
    assert (MsipAddr != MtimeHiAddr);
    assert (MtimecmpLoAddr != MtimecmpHiAddr);
    assert (MtimecmpLoAddr != MtimeLoAddr);
    assert (MtimecmpLoAddr != MtimeHiAddr);
    assert (MtimecmpHiAddr != MtimeLoAddr);
    assert (MtimecmpHiAddr != MtimeHiAddr);
    assert (MtimeLoAddr != MtimeHiAddr);
  end

  logic   _msip;
  dword_t _mtime;
  dword_t _mtimecmp;

  assign selected         = mem.req.valid &&
                            (mem.req.addr == MsipAddr ||
                             mem.req.addr == MtimecmpLoAddr ||
                             mem.req.addr == MtimecmpHiAddr ||
                             mem.req.addr == MtimeLoAddr ||
                             mem.req.addr == MtimeHiAddr);
  assign mem.rsp.ready = mem.req.valid & selected;

  always_comb begin
    mem.rsp.read_data = '0;
    if (mem.req.addr == MsipAddr) begin
      mem.rsp.read_data = {31'b0, _msip};
    end else if (mem.req.addr == MtimecmpLoAddr) begin
      mem.rsp.read_data = _mtimecmp[31:0];
    end else if (mem.req.addr == MtimecmpHiAddr) begin
      mem.rsp.read_data = _mtimecmp[63:32];
    end else if (mem.req.addr == MtimeLoAddr) begin
      mem.rsp.read_data = _mtime[31:0];
    end else if (mem.req.addr == MtimeHiAddr) begin
      mem.rsp.read_data = _mtime[63:32];
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _msip <= 1'b0;
      _mtime <= '0;
      _mtimecmp <= dword_t'({32'hffffffff, 32'hffffffff});
    end else begin
      _mtime <= _mtime + 1'b1;
      if (mem.req.valid && mem.req.write_en && selected) begin
        case (mem.req.addr)
          MsipAddr: begin
            _msip <= mem.req.write_data[0];
          end
          MtimecmpLoAddr: begin
            _mtimecmp[31:0] <= mem.req.write_data;
          end
          MtimecmpHiAddr: begin
            _mtimecmp[63:32] <= mem.req.write_data;
          end
          default: begin
          end
        endcase
      end
    end
  end

  always_comb begin
    irq.pending = '0;
    irq.pending.msip = _msip;
    irq.pending.mtip = (_mtime >= _mtimecmp);
  end

endmodule
