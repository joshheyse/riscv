`timescale 1ns / 1ps

module l1_cache
  import riscv_pkg::*;
#(
  parameter mem_addr_t CacheableBase = '0,
  parameter mem_addr_t CacheableEnd  = '0
) (
  input logic clk,
  input logic rst,

  mem_if.slave  upstream,
  mem_if.master downstream
);

  typedef enum logic [1:0] {
    IDLE,
    UNCACHED_REQUEST,
    UNCACHED_RESPONSE
  } state_t;

  initial begin
    assert (CacheableEnd >= CacheableBase);
  end

  logic   _cacheable;
  state_t _state;
  mem_if _to_cache ();
  mem_if _from_cache ();
  mem_req_t _request;

  generate
    if (CacheableBase == CacheableEnd) begin : GEN_NO_CACHEABLE_RANGE
      assign _cacheable = 1'b0;
    end else begin : GEN_CACHEABLE_RANGE
      assign _cacheable = (upstream.req.addr - CacheableBase) < (CacheableEnd - CacheableBase);
    end
  endgenerate

  direct_mapped_cache _cache (
    .clk(clk),
    .rst(rst),
    .upstream(_to_cache),
    .downstream(_from_cache)
  );

  always_comb begin
    upstream.rsp = '0;
    downstream.req = '0;
    _to_cache.req = '0;
    _from_cache.rsp = '0;
    if (_state == IDLE) begin
      if (_cacheable) begin
        _to_cache.req = upstream.req;
        upstream.rsp = _to_cache.rsp;
        downstream.req = _from_cache.req;
        _from_cache.rsp = downstream.rsp;
      end
    end else if (_state == UNCACHED_REQUEST) begin
      downstream.req = _request;
      upstream.rsp   = downstream.rsp;
    end else if (_state == UNCACHED_RESPONSE) begin
      // Keep driving the request. `mem_arbiter` ignores `req.valid` on cycles
      // it is not IDLE and gives no backpressure, so a request presented for a
      // single cycle is silently lost. Hold it until `rsp.ready`.
      upstream.rsp   = downstream.rsp;
      downstream.req = _request;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _state   <= IDLE;
      _request <= '0;
    end else begin
      unique case (_state)
        IDLE: begin
          if (upstream.req.valid) begin
            if (_cacheable) begin
              _state <= IDLE;
            end else begin
              _request <= upstream.req;
              _state   <= UNCACHED_REQUEST;
            end
          end
        end
        UNCACHED_REQUEST: begin
          if (downstream.rsp.ready) begin
            _state   <= IDLE;
            _request <= '0;
          end else begin
            _state <= UNCACHED_RESPONSE;
          end
        end
        UNCACHED_RESPONSE: begin
          if (downstream.rsp.ready) begin
            _state   <= IDLE;
            _request <= '0;
          end
        end
      endcase
    end
  end

endmodule
