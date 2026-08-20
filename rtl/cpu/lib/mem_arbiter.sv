`timescale 1ns / 1ps

// Two masters, one memory port, one transaction in flight.
//
// A port is granted only while the arbiter is idle, and its request transfers
// on the edge where the downstream slave also asserts `req_ready`. The grant is
// then latched so the response can be routed back to whoever owns it.
//
// There is no DRAIN state. The old one existed because a request was
// fire-and-forget: with no way for a slave to say "taken", a delayed slave
// could hold its response across an edge and be mistaken for answering the next
// requester. Acceptance is explicit now, and a slave answers exactly once per
// accepted request, so there is nothing left to drain.
module mem_arbiter (
  input logic         clk,
  input logic         rst,
        mem_if.slave  ifetch,
        mem_if.slave  data,
        mem_if.master mem
);

  typedef enum logic {
    IDLE = 1'b0,
    BUSY = 1'b1
  } state_t;

  typedef enum logic [1:0] {
    NONE   = 2'b00,
    IFETCH = 2'b01,
    DATA   = 2'b10
  } target_t;

  state_t  _state;
  target_t _target;
  target_t _grant;

  // Data wins a tie. Note that nothing here consults `req_ready`, which is what
  // lets `req_ready` depend combinationally on `req.valid` without closing a
  // loop -- see the handshake rules in mem_if.
  always_comb begin
    if (_state != IDLE) begin
      _grant = NONE;
    end else if (data.req.valid) begin
      _grant = DATA;
    end else if (ifetch.req.valid) begin
      _grant = IFETCH;
    end else begin
      _grant = NONE;
    end
  end

  always_comb begin
    mem.req = '0;
    if (_grant == DATA) begin
      mem.req = data.req;
    end else if (_grant == IFETCH) begin
      mem.req = '{
          valid: 1'b1,
          write_en: 1'b0,
          addr: ifetch.req.addr,
          write_data: '0,
          write_mask: '0
      };
    end

    // A master is accepted only on the cycle it holds the grant and the slave
    // takes the request.
    ifetch.req_ready = (_grant == IFETCH) && mem.req_ready;
    data.req_ready = (_grant == DATA) && mem.req_ready;

    // Route the response to whoever owns the transaction: the latched target
    // normally, or the port being granted right now if the slave answers in the
    // same cycle it accepts. Acceptance of that response comes back from the
    // same owner, so a master that cannot take it holds the slave off.
    ifetch.rsp = '0;
    data.rsp = '0;
    mem.rsp_ready = 1'b0;
    if (_target == IFETCH || (_state == IDLE && _grant == IFETCH)) begin
      ifetch.rsp = mem.rsp;
      mem.rsp_ready = ifetch.rsp_ready;
    end else if (_target == DATA || (_state == IDLE && _grant == DATA)) begin
      data.rsp = mem.rsp;
      mem.rsp_ready = data.rsp_ready;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _state  <= IDLE;
      _target <= NONE;
    end else begin
      unique case (_state)
        IDLE: begin
          if (mem.req.valid && mem.req_ready) begin
            if (mem.rsp.valid && mem.rsp_ready) begin
              // Zero-latency slave: accepted and answered in one cycle.
              _state  <= IDLE;
              _target <= NONE;
            end else begin
              _state  <= BUSY;
              _target <= _grant;
            end
          end
        end
        BUSY: begin
          if (mem.rsp.valid && mem.rsp_ready) begin
            _state  <= IDLE;
            _target <= NONE;
          end
        end
      endcase
    end
  end

endmodule
