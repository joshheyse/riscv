`timescale 1ns / 1ps

typedef enum logic [2:0] {
  I2C_IDLE      = 3'b000,
  I2C_START     = 3'b001,
  I2C_SEND_BYTE = 3'b010,
  I2C_ACK       = 3'b011,
  I2C_STOP      = 3'b100
} i2c_state_t;

typedef enum logic {
  I2C_PHASE_LOW  = 1'b0,
  I2C_PHASE_HIGH = 1'b1
} i2c_phase_t;

typedef enum logic {
  I2C_BYTE_ADDR = 1'b0,
  I2C_BYTE_DATA = 1'b1
} i2c_byte_t;

module i2c_mmio
  import riscv_pkg::*;
#(
  parameter mem_addr_t   DataAddr         = '0,
  parameter mem_addr_t   ControlAddr      = '0,
  parameter mem_addr_t   StatusAddr       = '0,
  parameter mem_addr_t   AddressAddr      = '0,
  parameter int unsigned ClocksPerHalfBit = 60
) (
  input  logic            clk,
  input  logic            rst,
  input  logic            mem_valid,
  input  logic            mem_write_en,
  input  mem_addr_t       mem_addr,
  input  mem_data_t       mem_write_data,
  input  mem_write_mask_t mem_write_mask,
  output logic            selected,
  output logic            mem_ready,
  output mem_data_t       mem_read_data,
  input  logic            i2c_sda_in,
  output logic            i2c_sda_drive_low,
  input  logic            i2c_scl_in,
  output logic            i2c_scl_drive_low
);

  i2c_state_t       _state;
  i2c_phase_t       _phase;
  i2c_byte_t        _byte_type;
  logic             _data_selected;
  logic             _control_selected;
  logic             _status_selected;
  logic             _address_selected;

  logic             _busy;
  logic             _ack_error;
  byte_t            _tx_data;
  byte_t            _rx_data;
  logic       [6:0] _i2c_addr;
  byte_t            _i2c_byte;
  logic       [2:0] _bit_index;

  assign _data_selected = mem_addr == DataAddr;
  assign _control_selected = mem_addr == ControlAddr;
  assign _status_selected = mem_addr == StatusAddr;
  assign _address_selected = mem_addr == AddressAddr;
  assign selected = _data_selected | _control_selected | _status_selected | _address_selected;
  assign mem_ready = mem_valid && selected;

  logic _stg_en;
  logic _stg_clear;
  logic _stg_tick;

  assign _stg_en = _state != I2C_IDLE;
  assign _stg_clear = !_stg_en;

  serial_tick_generator #(
    .ClocksPerTick(ClocksPerHalfBit)
  ) _tick_generator (
    .clk(clk),
    .rst(rst),
    .en(_stg_en),
    .clear(_stg_clear),
    .tick(_stg_tick)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      _state <= I2C_IDLE;
      _tx_data <= '0;
      _rx_data <= '0;
      _i2c_addr <= '0;
      _bit_index <= '0;
      _i2c_byte <= '0;
      _ack_error <= 1'b0;
      _phase <= I2C_PHASE_LOW;
      _byte_type <= I2C_BYTE_ADDR;
    end else begin
      if (mem_write_en) begin
        if (_data_selected) begin
          _tx_data <= mem_write_data[7:0];
        end else if (_address_selected) begin
          _i2c_addr <= mem_write_data[6:0];
        end
      end
      case (_state)
        I2C_IDLE: begin
          if (mem_write_en && _control_selected) begin
            _state <= I2C_START;
            _phase <= I2C_PHASE_LOW;
            _ack_error <= 1'b0;
          end
        end
        I2C_START: begin
          if (_stg_tick) begin
            if (_phase == I2C_PHASE_LOW) begin
              _phase <= I2C_PHASE_HIGH;
            end else begin
              _phase <= I2C_PHASE_LOW;
              _state <= I2C_SEND_BYTE;
              _bit_index <= 3'd7;
              _i2c_byte <= {_i2c_addr, 1'b0};
              _byte_type <= I2C_BYTE_ADDR;
            end
          end
        end
        I2C_SEND_BYTE: begin
          if (_stg_tick) begin
            if (_phase == I2C_PHASE_LOW) begin
              _phase <= I2C_PHASE_HIGH;
            end else begin
              _phase <= I2C_PHASE_LOW;
              if (_bit_index == 3'd0) begin
                _state <= I2C_ACK;
              end else begin
                _bit_index <= _bit_index - 1;
              end
            end
          end
        end
        I2C_ACK: begin
          if (_stg_tick) begin
            if (_phase == I2C_PHASE_LOW) begin
              _phase <= I2C_PHASE_HIGH;
            end else begin
              _phase <= I2C_PHASE_LOW;
              if (!i2c_sda_in) begin
                if (_byte_type == I2C_BYTE_ADDR) begin
                  _state     <= I2C_SEND_BYTE;
                  _bit_index <= 3'd7;
                  _i2c_byte  <= _tx_data;
                  _byte_type <= I2C_BYTE_DATA;
                end else begin
                  _state <= I2C_STOP;
                end
              end else begin
                _state <= I2C_STOP;
                _ack_error <= 1'b1;
              end
            end
          end
        end
        I2C_STOP: begin
          if (_stg_tick) begin
            if (_phase == I2C_PHASE_LOW) begin
              _phase <= I2C_PHASE_HIGH;
            end else begin
              _state <= I2C_IDLE;
              _phase <= I2C_PHASE_LOW;
            end
          end
        end
        default: begin
        end
      endcase
    end
  end

  always_comb begin
    _busy = 1'b0;
    i2c_sda_drive_low = 1'b0;
    i2c_scl_drive_low = 1'b0;
    case (_state)
      I2C_START, I2C_STOP: begin
        _busy = 1'b1;
        i2c_sda_drive_low = (_phase == I2C_PHASE_LOW);
        i2c_scl_drive_low = 1'b0;
      end
      I2C_SEND_BYTE: begin
        _busy = 1'b1;
        i2c_sda_drive_low = ~_i2c_byte[_bit_index];
        i2c_scl_drive_low = (_phase == I2C_PHASE_LOW);
      end
      I2C_ACK: begin
        _busy = 1'b1;
        i2c_sda_drive_low = 1'b0;
        i2c_scl_drive_low = (_phase == I2C_PHASE_LOW);
      end
      default: begin
      end
    endcase

    if (_data_selected) begin
      mem_read_data = {24'b0, _rx_data};
    end else if (_address_selected) begin
      mem_read_data = {25'b0, _i2c_addr};
    end else if (_status_selected) begin
      mem_read_data = {30'b0, _ack_error, _busy};
    end else begin
      mem_read_data = 32'b0;
    end

  end

  logic _unused_inputs;
  assign _unused_inputs = |i2c_scl_in | (|mem_write_data[31:8]) | (|mem_write_mask);


endmodule
