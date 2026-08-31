`timescale 1ns / 1ps

// Registered physical-side PMP boundary.
//
// The translation and cache hierarchy only presents physical requests here.
// A request is captured in IDLE, checked in CHECK, and either forwarded to the
// physical memory port in REQUEST or converted to a registered access-fault
// response.
// Successful responses carry the selected region's raw R/W/X permissions so a
// cache can retain them with the line and avoid putting the PMP interval scan
// on its hit path.
module pmp_annotator
  import riscv_pkg::*;
  import pmp_pkg::*;
#(
  parameter bit PmpEnabled = 1'b1
)
(
  input logic              clk,
  input logic              rst,
  input pmp_region_state_t pmp,

  mem_if.slave  upstream,
  mem_if.master downstream
);

  typedef enum logic [2:0] {
    IDLE,
    CHECK,
    REQUEST,
    WAIT,
    RESPONSE
  } state_e;

  state_e          _state;
  mem_req_t        _request;
  mem_rsp_t        _response;
  pmp_check_t      _check_result;
  pmp_check_t      _request_pmp_check;
  logic            _request_allowed;

  always_comb begin
    if (PmpEnabled) begin
      _check_result = pmp_check(
          pmp, _request.addr, _request.size, _request.access, _request.privilege);
    end else begin
      _check_result = '0;
      _check_result.allowed = 1'b1;
      _check_result.annotation = '{
          valid: 1'b1,
          read: 1'b1,
          write: 1'b1,
          execute: 1'b1
      };
    end
    _request_allowed = !PmpEnabled || _request_pmp_check.allowed;
  end

  always_comb begin
    upstream.req_ready = (_state == IDLE);
    upstream.rsp = (_state == RESPONSE) ? _response : '0;

    downstream.req = (_state == REQUEST && _request_allowed) ? _request : '0;
    downstream.rsp_ready = (_state == WAIT) ||
        ((_state == REQUEST) && _request_allowed);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _state <= IDLE;
      _request <= '0;
      _response <= '0;
      _request_pmp_check <= '0;
    end else begin
      unique case (_state)
        IDLE: begin
          if (upstream.req.valid && upstream.req_ready) begin
            _request <= upstream.req;
            _response <= '0;
            _state <= CHECK;
          end
        end
        CHECK: begin
          _request_pmp_check <= _check_result;
          _state <= REQUEST;
        end
        REQUEST: begin
          if (!_request_allowed) begin
            _response <= '{
                valid: 1'b1,
                read_data: '0,
                fault: MMU_FAULT_ACCESS,
                pmp_annotation: _request_pmp_check.annotation
            };
            _state <= RESPONSE;
          end else if (downstream.req.valid && downstream.req_ready) begin
            if (downstream.rsp.valid && downstream.rsp_ready) begin
              _response <= downstream.rsp;
              _response.pmp_annotation <= _request_pmp_check.annotation;
              _state <= RESPONSE;
            end else begin
              _state <= WAIT;
            end
          end
        end
        WAIT: begin
          if (downstream.rsp.valid && downstream.rsp_ready) begin
            _response <= downstream.rsp;
            _response.pmp_annotation <= _request_pmp_check.annotation;
            _state <= RESPONSE;
          end
        end
        RESPONSE: begin
          if (upstream.rsp.valid && upstream.rsp_ready) begin
            _response <= '0;
            _state <= IDLE;
          end
        end
        default: begin
          _state <= IDLE;
        end
      endcase
    end
  end

endmodule
