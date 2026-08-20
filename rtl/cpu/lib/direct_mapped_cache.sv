`timescale 1ns / 1ps

module direct_mapped_cache
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst,

  mem_if.slave  upstream,
  mem_if.master downstream
);



  // This master has somewhere to put every response it asked for, so it takes
  // them unconditionally. Drive it for real if that ever stops being true.
  assign downstream.rsp_ready = 1'b1;

  typedef logic [19:0] tag_t;
  typedef logic [6:0] set_index_t;
  typedef logic [4:0] offset_t;

  typedef struct packed {
    tag_t tag;
    set_index_t set;
    offset_t offset;
  } cache_line_address_t;

  typedef struct packed {
    logic valid;
    logic dirty;
    tag_t tag;
    logic [255:0] data;
  } cache_line_t;

  typedef enum logic [2:0] {
    IDLE,
    WRITE_BACK_REQUEST,
    WRITE_BACK_WAIT,
    REFILL_REQUEST,
    REFILL_WAIT,
    RESPOND
  } state_t;

  cache_line_t               _cache_data    [128];
  state_t                    _state;
  mem_req_t                  _request;
  logic                [2:0] _beat_idx;

  cache_line_address_t       _upstream_addr;
  cache_line_t               _upstream_line;
  logic                      _upstream_hit;


  cache_line_address_t       _request_addr;
  cache_line_t               _request_line;

  logic                      _beat_accepted;
  logic                      _beat_done;

  assign _upstream_addr = cache_line_address_t'(upstream.req.addr);
  assign _upstream_line = _cache_data[_upstream_addr.set];
  assign _upstream_hit  = _upstream_line.valid && _upstream_line.tag == _upstream_addr.tag;

  assign _request_addr  = cache_line_address_t'(_request.addr);
  assign _request_line  = _cache_data[_request_addr.set];

  always_comb begin
    upstream.rsp = '0;
    // A new upstream request is taken whenever the cache is idle: a hit is
    // answered in the same cycle, a miss is latched and answered after the
    // refill.
    upstream.req_ready = (_state == IDLE);
    downstream.req = '0;

    unique case (_state)
      IDLE: begin
        if (upstream.req.valid && _upstream_hit) begin
          upstream.rsp.valid = 1'b1;
          if (!upstream.req.write_en) begin
            upstream.rsp.read_data = _upstream_line.data[{_upstream_addr.offset[4:2], 5'b0}+:32];
          end
        end
      end

      // A beat stays presented until the slave accepts it. The WAIT states hold
      // an accepted beat while its response is outstanding, and drive nothing.
      WRITE_BACK_REQUEST: begin
        downstream.req = '{
            valid: 1'b1,
            write_en: 1'b1,
            addr: {_request_line.tag, _request_addr.set, _beat_idx, 2'b0},
            write_data: _request_line.data[{_beat_idx, 5'b0}+:32],
            write_mask: 4'b1111
        };
      end

      REFILL_REQUEST: begin
        downstream.req = '{
            valid: 1'b1,
            write_en: 1'b0,
            addr: {_request_addr.tag, _request_addr.set, _beat_idx, 2'b0},
            write_data: '0,
            write_mask: '0
        };
      end

      RESPOND: begin
        // The upstream master let go of its request when the cache accepted it,
        // so the response is unconditional.
        upstream.rsp.valid = 1'b1;
        if (!_request.write_en) begin
          upstream.rsp.read_data = _request_line.data[{_request_addr.offset[4:2], 5'b0}+:32];
        end
      end

      WRITE_BACK_WAIT, REFILL_WAIT: begin
      end
    endcase
  end

  // A beat transfers when it is both presented and accepted.
  assign _beat_accepted = downstream.req.valid && downstream.req_ready;
  assign _beat_done = downstream.rsp.valid;

  always_ff @(posedge clk) begin
    if (rst) begin
      _cache_data <= '{default: '0};
      _state <= IDLE;
      _request <= '0;
      _beat_idx <= '0;
    end else begin
      case (_state)
        IDLE: begin
          if (upstream.req.valid) begin
            if (_upstream_hit) begin
              if (upstream.req.write_en) begin
                for (int unsigned byte_idx = 0; byte_idx < 4; byte_idx++) begin
                  if (upstream.req.write_mask[byte_idx]) begin
                    _cache_data[_upstream_addr.set].data[
                      ({_upstream_addr.offset[4:2], 2'b0} + offset_t'(byte_idx)) * 8 +: 8
                    ] <= upstream.req.write_data[byte_idx*8 +: 8];
                  end
                end
                _cache_data[_upstream_addr.set].dirty <= 1'b1;
              end
            end else begin
              _request  <= upstream.req;
              _beat_idx <= '0;
              if (_upstream_line.valid && _upstream_line.dirty) begin
                _state <= WRITE_BACK_REQUEST;
              end else begin
                _state <= REFILL_REQUEST;
              end
            end
          end
        end

        // Each beat is presented until accepted, then waits for its
        // response before the next beat starts -- one transaction in flight.
        WRITE_BACK_REQUEST: begin
          if (_beat_accepted) begin
            if (_beat_done) begin
              if (_beat_idx == 3'd7) begin
                _beat_idx <= '0;
                _state <= REFILL_REQUEST;
              end else begin
                _beat_idx <= _beat_idx + 1'b1;
              end
            end else begin
              _state <= WRITE_BACK_WAIT;
            end
          end
        end

        WRITE_BACK_WAIT: begin
          if (_beat_done) begin
            if (_beat_idx == 3'd7) begin
              _beat_idx <= '0;
              _state <= REFILL_REQUEST;
            end else begin
              _beat_idx <= _beat_idx + 1'b1;
              _state <= WRITE_BACK_REQUEST;
            end
          end
        end

        REFILL_REQUEST: begin
          if (_beat_accepted) begin
            if (_beat_done) begin
              _cache_data[_request_addr.set].data[{
                _beat_idx, 5'b0
              }+:32] <= downstream.rsp.read_data;
              if (_beat_idx == 3'd7) begin
                _cache_data[_request_addr.set].tag <= _request_addr.tag;
                _cache_data[_request_addr.set].valid <= 1'b1;
                _cache_data[_request_addr.set].dirty <= 1'b0;
                _beat_idx <= '0;
                _state <= RESPOND;
              end else begin
                _beat_idx <= _beat_idx + 1'b1;
              end
            end else begin
              _state <= REFILL_WAIT;
            end
          end
        end

        REFILL_WAIT: begin
          if (_beat_done) begin
            _cache_data[_request_addr.set].data[{_beat_idx, 5'b0}+:32] <= downstream.rsp.read_data;
            if (_beat_idx == 3'd7) begin
              _cache_data[_request_addr.set].tag <= _request_addr.tag;
              _cache_data[_request_addr.set].valid <= 1'b1;
              _cache_data[_request_addr.set].dirty <= 1'b0;
              _beat_idx <= '0;
              _state <= RESPOND;
            end else begin
              _beat_idx <= _beat_idx + 1'b1;
              _state <= REFILL_REQUEST;
            end
          end
        end

        RESPOND: begin
          // The response is unconditional now, so the miss always completes
          // here rather than waiting for the master to still be asking.
          if (_request.write_en) begin
            for (int unsigned byte_idx = 0; byte_idx < 4; byte_idx++) begin
              if (_request.write_mask[byte_idx]) begin
                _cache_data[_request_addr.set].data[
                  ({_request_addr.offset[4:2], 2'b0} + offset_t'(byte_idx)) * 8 +: 8
                ] <= _request.write_data[byte_idx*8 +: 8];
              end
            end
            _cache_data[_request_addr.set].dirty <= 1'b1;
          end
          _state <= IDLE;
        end

        default: begin
          _state <= IDLE;
        end
      endcase
    end
  end

  // slang lint_off unused-net
  wire _unused_signal = &{
      1'b0,
      _upstream_addr.offset[1:0],
      _request_addr.offset[1:0],
      _request.valid,
      _request_line.valid,
      _request_line.dirty
  };
  // slang lint_on unused-net


endmodule
