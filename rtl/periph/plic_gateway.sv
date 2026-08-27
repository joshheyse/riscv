`timescale 1ns / 1ps

module plic_gateway (
  input  logic clk,
  input  logic rst,
  input  logic request,
  input  logic claim,
  input  logic complete,
  output logic pending
);

  typedef enum logic [1:0] {
    SOURCE_IDLE,
    SOURCE_PENDING,
    SOURCE_CLAIMED
  } source_state_e;

  source_state_e _state;

  always_ff @(posedge clk) begin
    if (rst) begin
      _state <= SOURCE_IDLE;
    end else begin
      unique case (_state)
        SOURCE_IDLE: begin
          if (request) begin
            _state <= SOURCE_PENDING;
          end
        end
        SOURCE_PENDING: begin
          if (claim) begin
            _state <= SOURCE_CLAIMED;
          end
        end
        SOURCE_CLAIMED: begin
          if (complete) begin
            _state <= request ? SOURCE_PENDING : SOURCE_IDLE;
          end
        end
      endcase
    end
  end

  assign pending = _state == SOURCE_PENDING;

endmodule
