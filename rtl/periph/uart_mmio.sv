`timescale 1ns / 1ps

typedef enum logic [2:0] {
  UART_RX_IDLE  = 3'b000,
  UART_RX_START = 3'b001,
  UART_RX_DATA  = 3'b010,
  UART_RX_STOP  = 3'b011
} uart_state_t;

module uart_mmio
  import riscv_pkg::*;
#(
  parameter int unsigned ClocksPerBit = 1,
  parameter mem_addr_t   TxDataAddr   = 32'h10001000,
  parameter mem_addr_t   RxDataAddr   = 32'h10001004,
  parameter mem_addr_t   StatusAddr   = 32'h1000100C
) (
  input  logic clk,
  input  logic rst,
  output logic selected,
  uart_if.source uart,

  mem_if.slave mem
);

  byte_t             _tx_data;
  logic        [3:0] _tx_bit_idx;
  logic              _tx_busy;
  logic              _tx_ready;
  logic        [2:0] _tx_data_bit_idx;
  logic              _rx_stg_tick;

  logic              _rx_busy;
  logic              _rx_ready;
  byte_t             _rx_data;
  logic        [2:0] _rx_bit_idx;
  logic              _tx_stg_tick;
  logic              _rx_overrun;
  logic              _rx_data_consumed;

  uart_state_t       _state;

  initial begin
    assert (TxDataAddr != StatusAddr);
    assert (TxDataAddr != RxDataAddr);
    assert (RxDataAddr != StatusAddr);
  end

  assign selected = (mem.req.addr == TxDataAddr || mem.req.addr == RxDataAddr || mem.req.addr == StatusAddr);
  assign mem.rsp.ready = mem.req.valid && selected;

  assign _tx_ready = !_tx_busy;
  always_comb begin
    _rx_data_consumed = mem.req.valid && !mem.req.write_en && (mem.req.addr == RxDataAddr) &&
                        selected && _rx_ready;

    mem.rsp.read_data = 32'h0;

    if (mem.req.addr == StatusAddr) begin
      mem.rsp.read_data = {29'b0, _rx_overrun, _rx_ready, _tx_ready};
    end else if (mem.req.addr == RxDataAddr) begin
      mem.rsp.read_data = {24'b0, _rx_data};
    end
  end

  assign _tx_data_bit_idx = _tx_bit_idx[2:0] - 3'd1;


  serial_tick_generator #(
    .ClocksPerTick(ClocksPerBit)
  ) _tx_tick_generator (
    .clk(clk),
    .rst(rst),
    .en(_tx_busy),
    .clear(!_tx_busy),
    .tick(_tx_stg_tick)
  );

  serial_tick_generator #(
    .ClocksPerTick(ClocksPerBit)
  ) _rx_tick_generator (
    .clk(clk),
    .rst(rst),
    .en(_rx_busy),
    .clear(!_rx_busy),
    .tick(_rx_stg_tick)
  );

  always_ff @(posedge clk) begin

    if (rst) begin
      _tx_busy <= 1'b0;
      _tx_data <= 8'h0;
      _tx_bit_idx <= '0;

      _rx_ready <= 1'b0;
      _rx_data <= 8'h0;
      _rx_busy <= 1'b0;
      _rx_bit_idx <= '0;
      _rx_overrun <= '0;

      _state <= UART_RX_IDLE;
    end else begin
      if (mem.req.write_en && (mem.req.addr == TxDataAddr) && !_tx_busy) begin
        _tx_busy <= 1'b1;
        _tx_data <= mem.req.write_data[7:0];
        _tx_bit_idx <= 0;
      end else if (_tx_busy) begin
        if (_tx_stg_tick) begin
          _tx_bit_idx <= _tx_bit_idx + 4'd1;
          if (_tx_bit_idx == 4'd9) begin
            _tx_busy <= 1'b0;
          end
        end
      end

      if (_rx_data_consumed) begin
        _rx_ready   <= 1'b0;
        _rx_overrun <= 1'b0;
      end else begin
        case (_state)
          UART_RX_IDLE: begin
            if (!uart.rx) begin
              _rx_overrun <= _rx_ready;
              _state <= UART_RX_START;
              _rx_bit_idx <= 3'd0;
              _rx_busy <= 1'b1;
              _rx_ready <= 1'b0;
            end
          end
          UART_RX_START: begin
            if (_rx_stg_tick) begin
              _state <= UART_RX_DATA;
              _rx_bit_idx <= 3'd0;
            end
          end
          UART_RX_DATA: begin
            if (_rx_stg_tick) begin
              _rx_data[_rx_bit_idx] <= uart.rx;
              _rx_bit_idx <= _rx_bit_idx + 3'd1;
              if (_rx_bit_idx == 3'd7) begin
                _state <= UART_RX_STOP;
              end
            end
          end
          UART_RX_STOP: begin
            if (_rx_stg_tick) begin
              _rx_busy <= 1'b0;
              _rx_ready <= 1'b1;
              _state <= UART_RX_IDLE;
            end
          end
          default: begin
          end
        endcase
      end
    end
  end

  always_comb begin
    if (!_tx_busy) begin
      uart.tx = 1'b1;
    end else if (_tx_bit_idx == 4'd0) begin
      uart.tx = 1'b0;
    end else if (_tx_bit_idx <= 4'd8) begin
      uart.tx = _tx_data[_tx_data_bit_idx];
    end else begin
      uart.tx = 1'b1;
    end
  end

endmodule
