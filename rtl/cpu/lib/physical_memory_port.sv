`timescale 1ns / 1ps

// Registered boundary between the core memory hierarchy and physical memory.
//
// One transaction may be outstanding. Both channels are registered: an
// upstream request is captured before being presented downstream, and a
// downstream response is captured before being presented upstream. This keeps
// a zero-cycle physical-memory slave from creating a combinational path through
// the complete cache, arbitration, and translation hierarchy.
module physical_memory_port
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst,

  mem_if.slave  upstream,
  mem_if.master downstream
);

  typedef enum logic [1:0] {
    IDLE,
    REQUEST,
    WAIT,
    RESPONSE
  } state_t;

  state_t   _state;
  mem_req_t _request;
  mem_rsp_t _response;

  always_comb begin
    upstream.req_ready = (_state == IDLE);
    upstream.rsp = (_state == RESPONSE) ? _response : '0;

    downstream.req = (_state == REQUEST) ? _request : '0;
    downstream.rsp_ready = (_state == REQUEST) || (_state == WAIT);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _state    <= IDLE;
      _request  <= '0;
      _response <= '0;
    end else begin
      unique case (_state)
        IDLE: begin
          if (upstream.req.valid && upstream.req_ready) begin
            _request <= upstream.req;
            _state   <= REQUEST;
          end
        end
        REQUEST: begin
          if (downstream.req.valid && downstream.req_ready) begin
            _request.valid <= 1'b0;
            if (downstream.rsp.valid && downstream.rsp_ready) begin
              _response <= downstream.rsp;
              _state    <= RESPONSE;
            end else begin
              _state <= WAIT;
            end
          end
        end
        WAIT: begin
          if (downstream.rsp.valid && downstream.rsp_ready) begin
            _response <= downstream.rsp;
            _state    <= RESPONSE;
          end
        end
        RESPONSE: begin
          if (upstream.rsp.valid && upstream.rsp_ready) begin
            _response <= '0;
            _state    <= IDLE;
          end
        end
      endcase
    end
  end

endmodule
