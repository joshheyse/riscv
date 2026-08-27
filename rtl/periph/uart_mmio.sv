`timescale 1ns / 1ps

typedef enum logic [2:0] {
  UART_RX_IDLE  = 3'b000,
  UART_RX_START = 3'b001,
  UART_RX_DATA  = 3'b010,
  UART_RX_STOP  = 3'b011
} uart_state_e;

module uart_mmio
  import riscv_pkg::*;
#(
  parameter int unsigned ClocksPerBit  = 1,
  parameter mem_addr_t   TxDataAddr    = 32'h10001000,
  parameter mem_addr_t   RxDataAddr    = 32'h10001004,
  parameter mem_addr_t   IrqEnableAddr = 32'h10001008,
  parameter mem_addr_t   StatusAddr    = 32'h1000100C
) (
  input logic clk,
  input logic rst,

  output logic selected,

  uart_if.source uart,
  mem_if.slave   mem,
  irq_if.source  irq
);


  // This slave can always take a request on the cycle it is presented, so
  // acceptance is unconditional. Drive it for real only if that changes.
  assign mem.req_ready = 1'b1;

  byte_t       _tx_data;
  logic  [3:0] _tx_bit_idx;
  logic        _tx_busy;
  logic        _tx_ready;
  logic  [2:0] _tx_data_bit_idx;

  logic        _rx_ready;
  byte_t       _rx_data;
  logic  [2:0] _rx_bit_idx;
  logic        _tx_stg_tick;
  logic        _rx_overrun;
  logic        _rx_data_consumed;
  logic        _rx_irq_en;
  logic        _rx_prev;

  localparam int unsigned RxCounterBits = (ClocksPerBit <= 1) ? 1 : $clog2(ClocksPerBit);
  localparam logic [RxCounterBits-1:0] RxHalfBitCount =
      RxCounterBits'(((ClocksPerBit + 1) / 2) - 1);
  localparam logic [RxCounterBits-1:0] RxFullBitCount = RxCounterBits'(ClocksPerBit - 1);
  logic        [RxCounterBits-1:0] _rx_counter;

  uart_state_e                     _state;

  initial begin
    assert (ClocksPerBit >= 2);
    assert (TxDataAddr != StatusAddr);
    assert (TxDataAddr != RxDataAddr);
    assert (RxDataAddr != StatusAddr);
    assert (IrqEnableAddr != StatusAddr);
    assert (IrqEnableAddr != TxDataAddr);
    assert (IrqEnableAddr != RxDataAddr);
  end

  assign selected = (mem.req.addr == TxDataAddr || mem.req.addr == RxDataAddr ||
                     mem.req.addr == IrqEnableAddr || mem.req.addr == StatusAddr);
  assign mem.rsp.valid = mem.req.valid && selected;

  assign _tx_ready = !_tx_busy;
  always_comb begin
    _rx_data_consumed = mem.req.valid && !mem.req.write_en && (mem.req.addr == RxDataAddr) &&
                        selected && _rx_ready;

    mem.rsp.read_data = 32'h0;

    if (mem.req.addr == StatusAddr) begin
      mem.rsp.read_data = {29'b0, _rx_overrun, _rx_ready, _tx_ready};
    end else if (mem.req.addr == RxDataAddr) begin
      mem.rsp.read_data = {24'b0, _rx_data};
    end else if (mem.req.addr == IrqEnableAddr) begin
      mem.rsp.read_data = {31'b0, _rx_irq_en};
    end


    irq.pending = '0;
    irq.pending.meip = _rx_irq_en && _rx_ready;
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

  always_ff @(posedge clk) begin

    if (rst) begin
      _tx_busy <= 1'b0;
      _tx_data <= 8'h0;
      _tx_bit_idx <= '0;

      _rx_ready <= 1'b0;
      _rx_data <= 8'h0;
      _rx_bit_idx <= '0;
      _rx_overrun <= '0;
      _rx_prev <= 1'b1;
      _rx_counter <= '0;

      _rx_irq_en <= 1'b0;

      _state <= UART_RX_IDLE;
    end else begin
      _rx_prev <= uart.rx;

      if (mem.req.write_en && mem.req.valid && (mem.req.addr == IrqEnableAddr)) begin
        _rx_irq_en <= mem.req.write_data[0];
      end
      if (mem.req.write_en && mem.req.valid && (mem.req.addr == TxDataAddr) && !_tx_busy) begin
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
            if (_rx_prev && !uart.rx) begin
              _rx_overrun <= _rx_ready;
              _state <= UART_RX_START;
              _rx_bit_idx <= 3'd0;
              _rx_ready <= 1'b0;
              _rx_counter <= RxHalfBitCount;
            end
          end
          UART_RX_START: begin
            if (_rx_counter == '0) begin
              if (!uart.rx) begin
                _state <= UART_RX_DATA;
                _rx_bit_idx <= 3'd0;
                _rx_counter <= RxFullBitCount;
              end else begin
                _state <= UART_RX_IDLE;
              end
            end else begin
              _rx_counter <= _rx_counter - 1'b1;
            end
          end
          UART_RX_DATA: begin
            if (_rx_counter == '0) begin
              _rx_data[_rx_bit_idx] <= uart.rx;
              _rx_bit_idx <= _rx_bit_idx + 3'd1;
              _rx_counter <= RxFullBitCount;
              if (_rx_bit_idx == 3'd7) begin
                _state <= UART_RX_STOP;
              end
            end else begin
              _rx_counter <= _rx_counter - 1'b1;
            end
          end
          UART_RX_STOP: begin
            if (_rx_counter == '0) begin
              _rx_ready <= uart.rx;
              _state <= UART_RX_IDLE;
            end else begin
              _rx_counter <= _rx_counter - 1'b1;
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
