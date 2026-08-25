`timescale 1ns / 1ps

module direct_mapped_cache
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst,

  mem_if.slave               upstream,
  mem_if.master              downstream,
  cache_command_if.responder cache_command
);
  localparam word_index_t _final_beat_idx = word_index_t'(CacheWordsPerLine - 1);

  typedef enum logic [3:0] {
    IDLE,
    MAINTENANCE,
    MAINTENANCE_NEXT,
    MAINTENANCE_RESPONSE,
    LOOKUP,
    WRITE_BACK_READ,
    WRITE_BACK_REQUEST,
    WRITE_BACK_WAIT,
    REFILL_REQUEST,
    REFILL_WAIT,
    REFILL_FINISH,
    RESPOND
  } state_t;

  typedef enum logic {
    WRITE_BACK_FOR_REFILL,
    WRITE_BACK_FOR_MAINTENANCE
  } write_back_reason_t;

  state_t              _state;
  mem_req_t            _request;
  word_index_t         _beat_idx;
  mem_data_t           _data_read_data;
  logic                _data_read_en;
  logic                _data_write_en;
  mem_write_mask_t     _data_write_mask;
  mem_data_t           _data_write_data;
  cache_line_address_t _request_addr;
  logic                _request_hit;
  logic                _beat_accepted;
  logic                _beat_done;
  logic                _response_transfer;
  cache_command_op_t   _command_op;
  write_back_reason_t  _write_back_reason;
  set_index_t          _write_back_set;
  tag_t                _write_back_tag;
  set_index_t          _maintenance_set;
  set_index_t          _way_set;
  word_index_t         _way_word_idx;
  tag_t                _way_install_tag;
  tag_t                _way_stored_tag;
  cache_meta_op_t      _way_meta_op;
  logic                _way_hit;
  logic                _way_valid;
  logic                _way_dirty;

  cache_way _cache_way (
    .clk(clk),
    .rst(rst),
    .set(_way_set),
    .lookup_tag(_request_addr.tag),
    .word_index(_way_word_idx),
    .data_read_en(_data_read_en),
    .data_write_en(_data_write_en),
    .write_data(_data_write_data),
    .write_mask(_data_write_mask),
    .meta_op(_way_meta_op),
    .install_tag(_way_install_tag),
    .hit(_way_hit),
    .valid(_way_valid),
    .dirty(_way_dirty),
    .stored_tag(_way_stored_tag),
    .read_data(_data_read_data)
  );

  assign downstream.rsp_ready = 1'b1;
  assign _request_addr = cache_line_address_t'(_request.addr);
  assign _request_hit = _way_hit;
  assign _beat_accepted = downstream.req.valid && downstream.req_ready;
  assign _beat_done = downstream.rsp.valid;
  assign _response_transfer = upstream.rsp.valid && upstream.rsp_ready;

  always_comb begin
    _way_set         = _request_addr.set;
    _way_word_idx    = _request_addr.offset[4:2];
    _way_meta_op     = META_NONE;
    _way_install_tag = '0;
    _data_read_en    = 1'b0;
    _data_write_en   = 1'b0;
    _data_write_mask = '0;
    _data_write_data = '0;

    // slang lint_off case-enum-explicit
    case (_state)
      IDLE: begin
        _way_set      = upstream.req.addr[11:5];
        _way_word_idx = upstream.req.addr[4:2];
        _data_read_en = upstream.req.valid;
      end

      MAINTENANCE: begin
        _way_set = _maintenance_set;
      end

      MAINTENANCE_NEXT: begin
        _way_set = _maintenance_set;
        if (_command_op.invalidate) begin
          _way_meta_op = META_INVALIDATE;
        end else if (_command_op.clean) begin
          _way_meta_op = META_CLEAR_DIRTY;
        end
      end

      WRITE_BACK_READ: begin
        _way_set      = _write_back_set;
        _way_word_idx = _beat_idx;
        _data_read_en = 1'b1;
      end

      REFILL_REQUEST, REFILL_WAIT: begin
        _way_word_idx = _beat_idx;
        if (_beat_done) begin
          _data_write_en   = 1'b1;
          _data_write_mask = '1;
          _data_write_data = downstream.rsp.read_data;
          if (_beat_idx == _final_beat_idx) begin
            _way_install_tag = _request_addr.tag;
            _way_meta_op = META_INSTALL;
          end
        end
      end

      REFILL_FINISH: begin
        _data_read_en = 1'b1;
      end

      LOOKUP, RESPOND: begin
        if (_response_transfer && _request.write_en) begin
          _way_meta_op = META_MARK_DIRTY;
          _data_write_en = 1'b1;
          _data_write_mask = _request.write_mask;
          _data_write_data = _request.write_data;
        end
      end

      default: begin
      end
    endcase
    // slang lint_on case-enum-explicit
  end

  always_comb begin
    cache_command.ready = (_state == IDLE);
    cache_command.done_valid = (_state == MAINTENANCE_RESPONSE);
    upstream.req_ready = (_state == IDLE && !cache_command.valid);
    upstream.rsp = '0;
    downstream.req = '0;
    // slang lint_off case-enum-explicit
    case (_state)
      WRITE_BACK_REQUEST: begin
        downstream.req = '{
            valid: 1'b1,
            write_en: 1'b1,
            addr: {_write_back_tag, _write_back_set, _beat_idx, 2'b0},
            write_data: _data_read_data,
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
          upstream.rsp.read_data = _data_read_data;
        end
      end
      default: begin
      end
    endcase
    // slang lint_on case-enum-explicit
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _state <= IDLE;
      _request <= '0;
      _beat_idx <= '0;
      _command_op <= '0;
    end else begin
      case (_state)
        IDLE: begin
          if (cache_command.valid) begin
            _state <= MAINTENANCE;
            _maintenance_set <= '0;
            _command_op <= cache_command.op;
          end else if (upstream.req.valid) begin
            _request <= upstream.req;
            _state   <= LOOKUP;
          end
        end
        MAINTENANCE: begin
          if (_command_op.clean && _way_valid && _way_dirty) begin
            _state <= WRITE_BACK_READ;
            _write_back_reason <= WRITE_BACK_FOR_MAINTENANCE;
            _write_back_set <= _maintenance_set;
            _write_back_tag <= _way_stored_tag;
            _beat_idx <= '0;
          end else begin
            _state <= MAINTENANCE_NEXT;
          end
        end
        MAINTENANCE_NEXT: begin
          if (_maintenance_set == set_index_t'(CacheNumSets - 1)) begin
            _state <= MAINTENANCE_RESPONSE;
          end else begin
            _maintenance_set <= _maintenance_set + 1'b1;
            _state <= MAINTENANCE;
          end
        end
        MAINTENANCE_RESPONSE: begin
          if (cache_command.done_valid && cache_command.done_ready) begin
            _state <= IDLE;
            _command_op <= '0;
          end
        end
        LOOKUP: begin
          if (_request_hit) begin
            if (_response_transfer) begin
              _state <= IDLE;
            end else begin
              _state <= RESPOND;
            end
          end else begin
            _beat_idx <= '0;
            if (_way_valid && _way_dirty) begin
              _state <= WRITE_BACK_READ;
              _write_back_reason <= WRITE_BACK_FOR_REFILL;
              _write_back_set <= _request_addr.set;
              _write_back_tag <= _way_stored_tag;
            end else begin
              _state <= REFILL_REQUEST;
            end
          end
        end
        WRITE_BACK_READ: begin
          _state <= WRITE_BACK_REQUEST;
        end
        WRITE_BACK_REQUEST: begin
          if (_beat_accepted) begin
            if (_beat_done) begin
              if (_beat_idx == _final_beat_idx) begin
                _beat_idx <= '0;
                _state <= _write_back_reason == WRITE_BACK_FOR_REFILL ? REFILL_REQUEST : MAINTENANCE_NEXT;
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
            if (_beat_idx == _final_beat_idx) begin
              _beat_idx <= '0;
              _state <= _write_back_reason == WRITE_BACK_FOR_REFILL ? REFILL_REQUEST : MAINTENANCE_NEXT;
            end else begin
              _beat_idx <= _beat_idx + 1'b1;
              _state <= WRITE_BACK_READ;
            end
          end
        end
        REFILL_REQUEST: begin
          if (_beat_accepted) begin
            if (_beat_done) begin
              if (_beat_idx == _final_beat_idx) begin
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
            if (_beat_idx == _final_beat_idx) begin
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
