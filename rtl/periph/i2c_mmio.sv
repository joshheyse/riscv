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
  parameter word_t DataAddr = '0,
  parameter word_t ControlAddr = '0,
  parameter word_t StatusAddr = '0,
  parameter word_t AddressAddr = '0,
  parameter int unsigned ClocksPerHalfBit = 60
) (
  input  logic  clk,
  input  logic  rst,
  input  logic  mem_write_en,
  input  word_t mem_addr,
  input  word_t mem_write_data,
  output logic  selected,
  output word_t read_data,
  input  logic  i2c_sda_in,
  output logic  i2c_sda_drive_low,
  input  logic  i2c_scl_in,
  output logic  i2c_scl_drive_low
);

  i2c_state_t state;
  i2c_phase_t phase;
  i2c_byte_t byte_type;
  logic data_selected;
  logic control_selected;
  logic status_selected;
  logic address_selected;

  logic busy;
  logic ack_error;
  byte_t tx_data;
  byte_t rx_data;
  logic [6:0] i2c_addr;
  byte_t i2c_byte;
  logic [2:0] bit_index;

  assign data_selected = mem_addr == DataAddr;
  assign control_selected = mem_addr == ControlAddr;
  assign status_selected = mem_addr == StatusAddr;
  assign address_selected = mem_addr == AddressAddr;
  assign selected = data_selected | control_selected | status_selected | address_selected;

  logic stg_enabled;
  logic stg_clear;
  logic stg_tick;

  assign stg_enabled = state != I2C_IDLE;
  assign stg_clear   = !stg_enabled;

  serial_tick_generator #(
    .ClocksPerTick(ClocksPerHalfBit)
  ) stg (
    .clk(clk),
    .rst(rst),
    .enable(stg_enabled),
    .clear(stg_clear),
    .tick(stg_tick)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= I2C_IDLE;
      tx_data <= '0;
      rx_data <= '0;
      i2c_addr <= '0;
      bit_index <= '0;
      i2c_byte <= '0;
      ack_error <= 1'b0;
      phase <= I2C_PHASE_LOW;
      byte_type <= I2C_BYTE_ADDR;
    end else begin
      if (mem_write_en) begin
        if (data_selected) begin
          tx_data <= mem_write_data[7:0];
        end else if (address_selected) begin
          i2c_addr <= mem_write_data[6:0];
        end
      end
      case (state)
        I2C_IDLE: begin
          if (mem_write_en && control_selected) begin
            state <= I2C_START;
            phase <= I2C_PHASE_LOW;
            ack_error <= 1'b0;
          end
        end
        I2C_START: begin
          if (stg_tick) begin
            if (phase == I2C_PHASE_LOW) begin
              phase <= I2C_PHASE_HIGH;
            end else begin
              phase <= I2C_PHASE_LOW;
              state <= I2C_SEND_BYTE;
              bit_index <= 3'd7;
              i2c_byte <= {i2c_addr, 1'b0};
              byte_type <= I2C_BYTE_ADDR;
            end
          end
        end
        I2C_SEND_BYTE: begin
          if (stg_tick) begin
            if (phase == I2C_PHASE_LOW) begin
              phase <= I2C_PHASE_HIGH;
            end else begin
              phase <= I2C_PHASE_LOW;
              if (bit_index == 3'd0) begin
                state <= I2C_ACK;
              end else begin
                bit_index <= bit_index - 1;
              end
            end
          end
        end
        I2C_ACK: begin
          if (stg_tick) begin
            if (phase == I2C_PHASE_LOW) begin
              phase <= I2C_PHASE_HIGH;
            end else begin
              phase <= I2C_PHASE_LOW;
              if (!i2c_sda_in) begin
                if (byte_type == I2C_BYTE_ADDR) begin
                  state     <= I2C_SEND_BYTE;
                  bit_index <= 3'd7;
                  i2c_byte  <= tx_data;
                  byte_type <= I2C_BYTE_DATA;
                end else begin
                  state <= I2C_STOP;
                end
              end else begin
                state <= I2C_STOP;
                ack_error <= 1'b1;
              end
            end
          end
        end
        I2C_STOP: begin
          if (stg_tick) begin
            if (phase == I2C_PHASE_LOW) begin
              phase <= I2C_PHASE_HIGH;
            end else begin
              state <= I2C_IDLE;
              phase <= I2C_PHASE_LOW;
            end
          end
        end
        default: begin
        end
      endcase
    end
  end

  always_comb begin
    busy = 1'b0;
    i2c_sda_drive_low = 1'b0;
    i2c_scl_drive_low = 1'b0;
    case (state)
      I2C_START, I2C_STOP: begin
        busy = 1'b1;
        i2c_sda_drive_low = (phase == I2C_PHASE_LOW);
        i2c_scl_drive_low = 1'b0;
      end
      I2C_SEND_BYTE: begin
        busy = 1'b1;
        i2c_sda_drive_low = ~i2c_byte[bit_index];
        i2c_scl_drive_low = (phase == I2C_PHASE_LOW);
      end
      I2C_ACK: begin
        busy = 1'b1;
        i2c_sda_drive_low = 1'b0;
        i2c_scl_drive_low = (phase == I2C_PHASE_LOW);
      end
      default: begin
      end
    endcase

    if (data_selected) begin
      read_data = {24'b0, rx_data};
    end else if (address_selected) begin
      read_data = {25'b0, i2c_addr};
    end else if (status_selected) begin
      read_data = {30'b0, ack_error, busy};
    end else begin
      read_data = 32'b0;
    end

  end

  logic unused_inputs;
  assign unused_inputs = |i2c_scl_in | (|mem_write_data[31:8]);


endmodule
