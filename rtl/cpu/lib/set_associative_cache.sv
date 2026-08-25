`timescale 1ns / 1ps

module set_associative_cache
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst,

  mem_if.slave               upstream,
  mem_if.master              downstream,
  cache_command_if.responder cache_command
);
  localparam word_index_t FinalBeatIdx = word_index_t'(CacheWordsPerLine - 1);

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

  state_t                                 _state;
  mem_req_t                               _request;
  word_index_t                            _beat_idx;
  logic                                   _data_read_en;
  mem_write_mask_t                        _data_write_mask;
  mem_data_t                              _data_write_data;
  cache_line_address_t                    _request_addr;
  logic                                   _request_hit;
  logic                                   _beat_accepted;
  logic                                   _beat_done;
  logic                                   _response_transfer;
  cache_command_op_t                      _command_op;
  write_back_reason_t                     _write_back_reason;
  set_index_t                             _write_back_set;
  tag_t                                   _write_back_tag;
  set_index_t                             _maintenance_set;
  set_index_t                             _way_set;
  word_index_t                            _way_word_idx;
  tag_t                                   _way_install_tag;
  logic                [CacheNumWays-1:0] _way_data_write_en;
  logic                [CacheNumWays-1:0] _way_hit;
  logic                [CacheNumWays-1:0] _way_valid;
  logic                [CacheNumWays-1:0] _way_dirty;
  tag_t                                   _way_stored_tag         [CacheNumWays];
  cache_meta_op_t                         _way_meta_op            [CacheNumWays];
  mem_data_t                              _way_read_data          [CacheNumWays];
  way_index_t                             _hit_way;
  way_index_t                             _victim_way;
  way_index_t                             _replacement_victim_way;
  way_index_t                             _victim_candidate_way;
  way_index_t                             _maintenance_way;
  logic                                   _lru_touch_valid;
  way_index_t                             _lru_touch_way;


  generate
    if (CacheNumWays == 2) begin : gen_lru_2_way
      lru_2_way _lru_2_way (
        .clk(clk),
        .rst(rst),
        .touch_valid(_lru_touch_valid),
        .touch_set(_request_addr.set),
        .touch_way(_lru_touch_way),
        .victim_set(_request_addr.set),
        .victim_way(_replacement_victim_way)
      );
    end else if (CacheNumWays == 4) begin : gen_lru_4_way
      lru_4_way _lru_4_way (
        .clk(clk),
        .rst(rst),
        .touch_valid(_lru_touch_valid),
        .touch_set(_request_addr.set),
        .touch_way(_lru_touch_way),
        .victim_set(_request_addr.set),
        .victim_way(_replacement_victim_way)
      );
    end else begin : gen_unsupported_way_count
      initial $error("CacheNumWays must be 2 or 4");
    end
  endgenerate

  assert property (@(posedge clk) $onehot0(_way_hit));

  generate
    for (genvar idx = 0; idx < CacheNumWays; idx++) begin : gen_cache_way
      cache_way _cache_way (
        .clk(clk),
        .rst(rst),
        .set(_way_set),
        .lookup_tag(_request_addr.tag),
        .word_index(_way_word_idx),
        .data_read_en(_data_read_en),
        .data_write_en(_way_data_write_en[idx]),
        .write_data(_data_write_data),
        .write_mask(_data_write_mask),
        .meta_op(_way_meta_op[idx]),
        .install_tag(_way_install_tag),
        .hit(_way_hit[idx]),
        .valid(_way_valid[idx]),
        .dirty(_way_dirty[idx]),
        .stored_tag(_way_stored_tag[idx]),
        .read_data(_way_read_data[idx])
      );
    end
  endgenerate

  assign downstream.rsp_ready = 1'b1;
  assign _request_addr = cache_line_address_t'(_request.addr);
  assign _beat_accepted = downstream.req.valid && downstream.req_ready;
  assign _beat_done = downstream.rsp.valid;
  assign _response_transfer = upstream.rsp.valid && upstream.rsp_ready;

  always_comb begin
    _request_hit          = |_way_hit;
    _hit_way              = '0;
    _victim_candidate_way = '0;

    for (int unsigned idx = 0; idx < CacheNumWays; idx++) begin
      if (_way_hit[idx]) begin
        _hit_way = way_index_t'(idx);
      end
    end

    if (&_way_valid) begin
      _victim_candidate_way = _replacement_victim_way;
    end else begin
      for (int unsigned idx = 0; idx < CacheNumWays; idx++) begin
        if (!_way_valid[idx]) begin
          _victim_candidate_way = way_index_t'(idx);
        end
      end
    end

  end

  always_comb begin
    _lru_touch_valid = 1'b0;
    _lru_touch_way   = '0;

    // slang lint_off case-enum-explicit
    case (_state)
      LOOKUP, RESPOND: begin
        if (_request_hit && _response_transfer) begin
          _lru_touch_valid = 1'b1;
          _lru_touch_way   = _hit_way;
        end
      end

      REFILL_REQUEST, REFILL_WAIT: begin
        if (_beat_done && _beat_idx == FinalBeatIdx) begin
          _lru_touch_valid = 1'b1;
          _lru_touch_way   = _victim_way;
        end
      end
      default: begin
      end
    endcase
    // slang lint_on case-enum-explicit
  end

  always_comb begin
    for (int unsigned idx = 0; idx < CacheNumWays; idx++) begin
      _way_meta_op[idx] = META_NONE;
    end
    _way_set           = _request_addr.set;
    _way_word_idx      = _request_addr.offset[CacheLineOffsetBits-1:2];
    _way_install_tag   = '0;
    _data_read_en      = 1'b0;
    _way_data_write_en = '0;
    _data_write_mask   = '0;
    _data_write_data   = '0;

    // slang lint_off case-enum-explicit
    case (_state)
      IDLE: begin
        _way_set      = upstream.req.addr[CacheLineOffsetBits+:CacheSetIndexBits];
        _way_word_idx = upstream.req.addr[2+:CacheWordIndexBits];
        _data_read_en = upstream.req.valid;
      end

      MAINTENANCE: begin
        _way_set = _maintenance_set;
      end

      MAINTENANCE_NEXT: begin
        _way_set = _maintenance_set;

        if (_command_op.invalidate) begin
          _way_meta_op[_maintenance_way] = META_INVALIDATE;
        end else if (_command_op.clean) begin
          _way_meta_op[_maintenance_way] = META_CLEAR_DIRTY;
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
          _way_data_write_en[_victim_way] = 1'b1;
          _data_write_mask = '1;
          _data_write_data = downstream.rsp.read_data;
          if (_beat_idx == FinalBeatIdx) begin
            _way_install_tag = _request_addr.tag;
            _way_meta_op[_victim_way] = META_INSTALL;
          end
        end
      end

      REFILL_FINISH: begin
        _data_read_en = 1'b1;
      end

      LOOKUP, RESPOND: begin
        if (_response_transfer && _request.write_en) begin
          _way_meta_op[_hit_way] = META_MARK_DIRTY;
          _way_data_write_en[_hit_way] = 1'b1;
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
            write_data:
            _way_read_data[
            (_write_back_reason==WRITE_BACK_FOR_REFILL)?_victim_way : _maintenance_way
            ],
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
          upstream.rsp.read_data = _way_read_data[_hit_way];
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
      _victim_way <= '0;
    end else begin
      case (_state)
        IDLE: begin
          if (cache_command.valid) begin
            _state <= MAINTENANCE;
            _maintenance_way <= '0;
            _maintenance_set <= '0;
            _command_op <= cache_command.op;
          end else if (upstream.req.valid) begin
            _request <= upstream.req;
            _state   <= LOOKUP;
          end
        end
        MAINTENANCE: begin
          if (_command_op.clean && _way_valid[_maintenance_way] && _way_dirty[_maintenance_way]) begin
            _state <= WRITE_BACK_READ;
            _write_back_reason <= WRITE_BACK_FOR_MAINTENANCE;
            _write_back_set <= _maintenance_set;
            _write_back_tag <= _way_stored_tag[_maintenance_way];
            _beat_idx <= '0;
          end else begin
            _state <= MAINTENANCE_NEXT;
          end
        end
        MAINTENANCE_NEXT: begin
          if (_maintenance_way == way_index_t'(CacheNumWays - 1)) begin
            _maintenance_way <= '0;
            if (_maintenance_set == set_index_t'(CacheNumSets - 1)) begin
              _state <= MAINTENANCE_RESPONSE;
            end else begin
              _maintenance_set <= _maintenance_set + 1'b1;
              _state <= MAINTENANCE;
            end
          end else begin
            _maintenance_way <= _maintenance_way + 1'b1;
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
            _beat_idx   <= '0;
            _victim_way <= _victim_candidate_way;
            if (_way_valid[_victim_candidate_way] && _way_dirty[_victim_candidate_way]) begin
              _state <= WRITE_BACK_READ;
              _write_back_reason <= WRITE_BACK_FOR_REFILL;
              _write_back_set <= _request_addr.set;
              _write_back_tag <= _way_stored_tag[_victim_candidate_way];
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
              if (_beat_idx == FinalBeatIdx) begin
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
            if (_beat_idx == FinalBeatIdx) begin
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
              if (_beat_idx == FinalBeatIdx) begin
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
            if (_beat_idx == FinalBeatIdx) begin
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
