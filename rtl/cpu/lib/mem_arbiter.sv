`timescale 1ns / 1ps

module mem_arbiter (
  input logic         clk,
  input logic         rst,
        mem_if.slave  ifetch,
        mem_if.slave  data,
        mem_if.master mem
);

  typedef enum logic [1:0] {
    IDLE  = 2'b00,
    BUSY  = 2'b01,
    DRAIN = 2'b10
  } state_t;

  typedef enum logic [1:0] {
    NONE   = 2'b00,
    IFETCH = 2'b01,
    DATA   = 2'b10
  } target_t;

  state_t  _state;
  target_t _target;

  always_ff @(posedge clk) begin
    if (rst) begin
      _state  <= IDLE;
      _target <= NONE;
    end else begin
      unique case (_state)
        IDLE: begin
          if (ifetch.req.valid || data.req.valid) begin
            if (mem.rsp.ready) begin
              _state  <= IDLE;
              _target <= NONE;
            end else begin
              _state  <= BUSY;
              _target <= data.req.valid ? DATA : IFETCH;
            end
          end
        end
        BUSY: begin
          if (mem.rsp.ready) begin
            // Delayed slaves may keep `ready` asserted through this edge.
            // Drain that old response before granting a different requester.
            _state  <= DRAIN;
            _target <= NONE;
          end
        end
        DRAIN: begin
          _state <= IDLE;
        end
      endcase
    end
  end


  always_comb begin
    ifetch.rsp = '0;
    data.rsp   = '0;

    if (_state == IDLE && data.req.valid) begin
      mem.req.addr = data.req.addr;
      mem.req.write_data = data.req.write_data;
      mem.req.write_en = data.req.write_en;
      mem.req.write_mask = data.req.write_mask;
      mem.req.valid = 1'b1;
      data.rsp = mem.rsp;
    end else if (_state == IDLE && ifetch.req.valid) begin
      mem.req.addr = ifetch.req.addr;
      mem.req.valid = 1'b1;
      mem.req.write_en = 1'b0;
      mem.req.write_data = '0;
      mem.req.write_mask = '0;
      ifetch.rsp = mem.rsp;
    end else begin
      mem.req.addr = '0;
      mem.req.write_data = '0;
      mem.req.valid = 1'b0;
      mem.req.write_en = 1'b0;
      mem.req.write_mask = '0;
    end

    if (_target == IFETCH) begin
      ifetch.rsp = mem.rsp;
    end else if (_target == DATA) begin
      data.rsp = mem.rsp;
    end
  end

endmodule
