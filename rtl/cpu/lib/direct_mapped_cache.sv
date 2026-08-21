`timescale 1ns / 1ps

module direct_mapped_cache
  import riscv_pkg::*;
(
  input logic         clk,
  input logic         rst,
        mem_if.slave  upstream,
        mem_if.master downstream
);
  localparam int unsigned NumSets = 128;
  localparam int unsigned WordsPerLine = 8;
  typedef logic [19:0] tag_t;
  typedef logic [6:0] set_index_t;
  typedef logic [4:0] offset_t;
  typedef logic [9:0] data_index_t;
  typedef struct packed {
    tag_t tag;
    set_index_t set;
    offset_t offset;
  } cache_line_address_t;
  typedef enum logic [3:0] {
    IDLE,
    LOOKUP,
    WRITE_BACK_READ,
    WRITE_BACK_REQUEST,
    WRITE_BACK_WAIT,
    REFILL_REQUEST,
    REFILL_WAIT,
    REFILL_FINISH,
    RESPOND
  } state_t;

  // Reset metadata only. The word array has the synchronous ports required for
  // ECP5 block RAM and deliberately has no reset assignment.
  (* ram_style = "block" *)logic                [       31:0] _data              [NumSets*WordsPerLine];
  tag_t                              _tags              [             NumSets];
  logic                [NumSets-1:0] _valid;
  logic                [NumSets-1:0] _dirty;
  state_t                            _state;
  mem_req_t                          _request;
  logic                [        2:0] _beat_idx;
  mem_data_t                         _data_read;
  data_index_t                       _data_read_addr;
  logic                              _data_read_en;
  data_index_t                       _data_write_addr;
  logic                              _data_write_en;
  mem_write_mask_t                   _data_write_mask;
  mem_data_t                         _data_write_data;
  cache_line_address_t               _request_addr;
  logic                              _request_hit;
  logic                              _beat_accepted;
  logic                              _beat_done;
  logic                              _response_transfer;

  assign downstream.rsp_ready = 1'b1;
  assign _request_addr = cache_line_address_t'(_request.addr);
  assign _request_hit = _valid[_request_addr.set] && _tags[_request_addr.set] == _request_addr.tag;
  assign _beat_accepted = downstream.req.valid && downstream.req_ready;
  assign _beat_done = downstream.rsp.valid;
  assign _response_transfer = upstream.rsp.valid && upstream.rsp_ready;

  always_comb begin
    _data_read_addr = {_request_addr.set, _request_addr.offset[4:2]};
    _data_read_en   = (_state == REFILL_FINISH);
    if (_state == IDLE) begin
      _data_read_addr = upstream.req.addr[11:2];
      _data_read_en   = upstream.req.valid;
    end else if (_state == WRITE_BACK_READ) begin
      _data_read_addr = {_request_addr.set, _beat_idx};
      _data_read_en   = 1'b1;
    end

    _data_write_en   = 1'b0;
    _data_write_addr = {_request_addr.set, _request_addr.offset[4:2]};
    _data_write_mask = '0;
    _data_write_data = '0;
    if ((_state == REFILL_REQUEST || _state == REFILL_WAIT) && _beat_done) begin
      _data_write_en   = 1'b1;
      _data_write_addr = {_request_addr.set, _beat_idx};
      _data_write_mask = 4'b1111;
      _data_write_data = downstream.rsp.read_data;
    end else if ((_state == LOOKUP || _state == RESPOND) && _response_transfer &&
                 _request.write_en) begin
      _data_write_en   = 1'b1;
      _data_write_mask = _request.write_mask;
      _data_write_data = _request.write_data;
    end
  end

  always_ff @(posedge clk) begin
    if (_data_read_en) begin
      _data_read <= _data[_data_read_addr];
    end
    if (_data_write_en) begin
      for (int unsigned byte_idx = 0; byte_idx < 4; byte_idx++) begin
        if (_data_write_mask[byte_idx]) begin
          _data[_data_write_addr][byte_idx*8+:8] <= _data_write_data[byte_idx*8+:8];
        end
      end
    end
  end

  always_comb begin
    upstream.req_ready = (_state == IDLE);
    upstream.rsp = '0;
    downstream.req = '0;
    case (_state)
      WRITE_BACK_REQUEST: begin
        downstream.req = '{
            valid: 1'b1,
            write_en: 1'b1,
            addr: {_tags[_request_addr.set], _request_addr.set, _beat_idx, 2'b0},
            write_data: _data_read,
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
      LOOKUP, RESPOND: begin
        upstream.rsp.valid = (_state == RESPOND) || _request_hit;
        if (!_request.write_en) begin
          upstream.rsp.read_data = _data_read;
        end
      end
      default: begin
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _state <= IDLE;
      _request <= '0;
      _beat_idx <= '0;
      _valid <= '0;
      _dirty <= '0;
    end else begin
      case (_state)
        IDLE: begin
          if (upstream.req.valid) begin
            _request <= upstream.req;
            _state   <= LOOKUP;
          end
        end
        LOOKUP: begin
          if (_request_hit) begin
            if (_response_transfer) begin
              if (_request.write_en) begin
                _dirty[_request_addr.set] <= 1'b1;
              end
              _state <= IDLE;
            end else begin
              _state <= RESPOND;
            end
          end else begin
            _beat_idx <= '0;
            _state <= (_valid[_request_addr.set] && _dirty[_request_addr.set]) ?
                WRITE_BACK_READ : REFILL_REQUEST;
          end
        end
        WRITE_BACK_READ: begin
          _state <= WRITE_BACK_REQUEST;
        end
        WRITE_BACK_REQUEST: begin
          if (_beat_accepted) begin
            if (_beat_done) begin
              if (_beat_idx == 3'd7) begin
                _beat_idx <= '0;
                _state <= REFILL_REQUEST;
              end else begin
                _beat_idx <= _beat_idx + 1'b1;
                _state <= WRITE_BACK_READ;
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
              _state <= WRITE_BACK_READ;
            end
          end
        end
        REFILL_REQUEST: begin
          if (_beat_accepted) begin
            if (_beat_done) begin
              if (_beat_idx == 3'd7) begin
                _tags[_request_addr.set] <= _request_addr.tag;
                _valid[_request_addr.set] <= 1'b1;
                _dirty[_request_addr.set] <= 1'b0;
                _beat_idx <= '0;
                _state <= REFILL_FINISH;
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
            if (_beat_idx == 3'd7) begin
              _tags[_request_addr.set] <= _request_addr.tag;
              _valid[_request_addr.set] <= 1'b1;
              _dirty[_request_addr.set] <= 1'b0;
              _beat_idx <= '0;
              _state <= REFILL_FINISH;
            end else begin
              _beat_idx <= _beat_idx + 1'b1;
              _state <= REFILL_REQUEST;
            end
          end
        end
        REFILL_FINISH: begin
          _state <= RESPOND;
        end
        RESPOND: begin
          if (_response_transfer) begin
            if (_request.write_en) begin
              _dirty[_request_addr.set] <= 1'b1;
            end
            _state <= IDLE;
          end
        end
        default: begin
          _state <= IDLE;
        end
      endcase
    end
  end

  // slang lint_off unused-net
  wire _unused_signal = &{1'b0, upstream.req.addr[1:0], _request_addr.offset[1:0], _request.valid};
  // slang lint_on unused-net
endmodule
