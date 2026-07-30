`timescale 1ns / 1ps

typedef enum logic [2:0] {
  I2C_IDLE      = 3'b000,
  I2C_START     = 3'b001,
  I2C_SEND_ADDR = 3'b010,
  I2C_ADDR_ACK  = 3'b011,
  I2C_SEND_DATA = 3'b100,
  I2C_DATA_ACK  = 3'b101,
  I2C_STOP      = 3'b110,
  I2C_DONE      = 3'b111
} i2c_state_t;

typedef enum logic {
  I2C_PHASE_LOW  = 1'b0,
  I2C_PHASE_HIGH = 1'b1
} i2c_phase_t;

module i2c_mmio #(
  parameter riscv_pkg::word_t DataAddr = memmap_pkg::I2cDataAddr,
  parameter riscv_pkg::word_t ControlAddr = memmap_pkg::I2cControlAddr,
  parameter riscv_pkg::word_t StatusAddr = memmap_pkg::I2cStatusAddr,
  parameter riscv_pkg::word_t AddressAddr = memmap_pkg::I2cAddressAddr,
  parameter int unsigned ClocksPerHalfBit = 60
) (
  input logic clk,
  input logic rst,
  input logic mem_write,
  input riscv_pkg::word_t mem_addr,
  input riscv_pkg::word_t mem_write_data,
  output logic selected,
  output riscv_pkg::word_t read_data,
  input logic i2c_sda_in,
  output logic i2c_sda_drive_low,
  input logic i2c_scl_in,
  output logic i2c_scl_drive_low
);

  i2c_state_t state;
  i2c_phase_t phase;
  logic data_selected;
  logic control_selected;
  logic status_selected;
  logic address_selected;

  logic busy;
  logic ack_error;
  riscv_pkg::byte_t tx_data;
  riscv_pkg::byte_t rx_data;
  logic [6:0] i2c_addr;
  riscv_pkg::byte_t i2c_byte;
  logic [2:0] bit_index;

  localparam int unsigned I2cCounterBits = (ClocksPerHalfBit <= 1) ? 1 : $clog2(ClocksPerHalfBit);

  logic [I2cCounterBits-1:0] i2c_counter;
  logic half_bit_done;

  assign half_bit_done = i2c_counter == I2cCounterBits'(ClocksPerHalfBit - 1);

  assign data_selected = mem_addr == DataAddr;
  assign control_selected = mem_addr == ControlAddr;
  assign status_selected = mem_addr == StatusAddr;
  assign address_selected = mem_addr == AddressAddr;
  assign selected = data_selected || control_selected || status_selected || address_selected;

  assign i2c_byte = {i2c_addr, 1'b0};

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= I2C_IDLE;
      tx_data <= 0;
      rx_data <= 0;
      i2c_addr <= 0;
      bit_index <= 0;
      phase <= I2C_PHASE_LOW;
      i2c_counter <= 0;
      ack_error <= 0;
    end else begin
      if (mem_write) begin
        if (data_selected) begin
          tx_data <= mem_write_data[7:0];
        end else if (address_selected) begin
          i2c_addr <= mem_write_data[6:0];
        end
      end
      case (state)
        I2C_IDLE: begin
          if (mem_write && control_selected) begin
            state <= I2C_START;
            phase <= I2C_PHASE_LOW;
            i2c_counter <= 0;
            ack_error <= 1'b0;
          end
        end
        I2C_START: begin
          if (half_bit_done) begin
            if (phase == I2C_PHASE_LOW) begin
              phase <= I2C_PHASE_HIGH;
            end else begin
              phase <= I2C_PHASE_LOW;
              state <= I2C_SEND_ADDR;
              bit_index <= 3'd7;
            end
            i2c_counter <= 0;
          end else begin
            i2c_counter <= i2c_counter + I2cCounterBits'(1'b1);
          end
        end
        I2C_SEND_ADDR: begin
          if (half_bit_done) begin
            if (phase == I2C_PHASE_LOW) begin
              phase <= I2C_PHASE_HIGH;
            end else begin
              phase <= I2C_PHASE_LOW;
              if (bit_index == 3'd0) begin
                state <= I2C_ADDR_ACK;
              end else begin
                bit_index <= bit_index - 1;
              end
            end
            i2c_counter <= 0;
          end else begin
            i2c_counter <= i2c_counter + I2cCounterBits'(1'b1);
          end
        end
        I2C_ADDR_ACK: begin
          if (half_bit_done) begin
            i2c_counter <= '0;
            if (phase == I2C_PHASE_LOW) begin
              phase <= I2C_PHASE_HIGH;
            end else begin
              if (!i2c_sda_in) begin
                state     <= I2C_SEND_DATA;
                phase     <= I2C_PHASE_LOW;
                bit_index <= 3'd7;
              end else begin
                state <= I2C_STOP;
                phase <= I2C_PHASE_LOW;
                ack_error <= 1'b1;
              end
            end
          end else begin
            i2c_counter <= i2c_counter + I2cCounterBits'(1'b1);
          end
        end
        I2C_SEND_DATA: begin
          if (half_bit_done) begin
            if (phase == I2C_PHASE_LOW) begin
              phase <= I2C_PHASE_HIGH;
            end else begin
              phase <= I2C_PHASE_LOW;
              if (bit_index == 3'd0) begin
                state <= I2C_DATA_ACK;
              end else begin
                bit_index <= bit_index - 1;
              end
            end
            i2c_counter <= 0;
          end else begin
            i2c_counter <= i2c_counter + I2cCounterBits'(1'b1);
          end
        end
        I2C_DATA_ACK: begin
          if (half_bit_done) begin
            i2c_counter <= '0;

            if (phase == I2C_PHASE_LOW) begin
              phase <= I2C_PHASE_HIGH;
            end else begin
              if (!i2c_sda_in) begin
                state <= I2C_STOP;
                phase <= I2C_PHASE_LOW;
              end else begin
                state <= I2C_STOP;
                phase <= I2C_PHASE_LOW;
                ack_error <= 1'b1;
              end
            end
          end else begin
            i2c_counter <= i2c_counter + I2cCounterBits'(1'b1);
          end
        end
        I2C_STOP: begin
          if (half_bit_done) begin
            if (phase == I2C_PHASE_LOW) begin
              phase <= I2C_PHASE_HIGH;
            end else begin
              state <= I2C_IDLE;
              phase <= I2C_PHASE_LOW;
            end
            i2c_counter <= 0;
          end else begin
            i2c_counter <= i2c_counter + I2cCounterBits'(1'b1);
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
      I2C_START: begin
        busy = 1'b1;
        i2c_sda_drive_low = (phase == I2C_PHASE_LOW);
        i2c_scl_drive_low = 1'b0;
      end
      I2C_SEND_ADDR: begin
        busy = 1'b1;
        i2c_sda_drive_low = ~i2c_byte[bit_index];
        i2c_scl_drive_low = (phase == I2C_PHASE_LOW);
      end
      I2C_ADDR_ACK: begin
        busy = 1'b1;
        i2c_sda_drive_low = 1'b0;  // release for slave ACK
        i2c_scl_drive_low = (phase == I2C_PHASE_LOW);
      end
      I2C_SEND_DATA: begin
        busy = 1'b1;
        i2c_sda_drive_low = ~tx_data[bit_index];
        i2c_scl_drive_low = (phase == I2C_PHASE_LOW);
      end
      I2C_DATA_ACK: begin
        busy = 1'b1;
        i2c_sda_drive_low = 1'b0;  // release for slave ACK
        i2c_scl_drive_low = (phase == I2C_PHASE_LOW);
      end
      I2C_STOP: begin
        busy = 1'b1;
        i2c_sda_drive_low = (phase == I2C_PHASE_LOW);
        i2c_scl_drive_low = 1'b0;
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
  assign unused_inputs = |i2c_scl_in | (|mem_write_data);


endmodule
