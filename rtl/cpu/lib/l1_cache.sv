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
    UNCACHED_REQUEST,  // latched, presented downstream, not yet accepted
    UNCACHED_WAIT      // accepted downstream, response outstanding
  } state_t;

  initial begin
    assert (CacheableEnd >= CacheableBase);
  end

  logic   _cacheable;
  state_t _state;
  mem_if _to_cache (
    clk,
    rst
  );
  mem_if _from_cache (
    clk,
    rst
  );
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
    upstream.req_ready = 1'b0;
    downstream.req = '0;
    downstream.rsp_ready = 1'b0;
    _to_cache.req = '0;
    _to_cache.rsp_ready = 1'b0;
    _from_cache.req_ready = 1'b0;
    _from_cache.rsp = '0;

    if (_state == IDLE) begin
      if (_cacheable) begin
        // Straight through: the cache decides when it can take the request,
        // and its own refill traffic is what reaches the bus.
        _to_cache.req = upstream.req;
        upstream.req_ready = _to_cache.req_ready;
        upstream.rsp = _to_cache.rsp;
        _to_cache.rsp_ready = upstream.rsp_ready;
        downstream.req = _from_cache.req;
        _from_cache.req_ready = downstream.req_ready;
        _from_cache.rsp = downstream.rsp;
        downstream.rsp_ready = _from_cache.rsp_ready;
      end else begin
        // Uncached: take the request here and replay it downstream, so the
        // upstream master is released immediately.
        upstream.req_ready = 1'b1;
      end
    end else if (_state == UNCACHED_REQUEST) begin
      downstream.req = _request;
      upstream.rsp = downstream.rsp;
      downstream.rsp_ready = upstream.rsp_ready;
    end else if (_state == UNCACHED_WAIT) begin
      upstream.rsp = downstream.rsp;
      downstream.rsp_ready = upstream.rsp_ready;
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
          if (downstream.req.valid && downstream.req_ready) begin
            if (downstream.rsp.valid && downstream.rsp_ready) begin
              _state   <= IDLE;
              _request <= '0;
            end else begin
              _state <= UNCACHED_WAIT;
            end
          end
        end
        UNCACHED_WAIT: begin
          if (downstream.rsp.valid && downstream.rsp_ready) begin
            _state   <= IDLE;
            _request <= '0;
          end
        end
      endcase
    end
  end

endmodule
