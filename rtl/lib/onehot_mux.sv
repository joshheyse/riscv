`timescale 1ns / 1ps

module onehot_mux #(
  parameter int unsigned Width     = 32,
  parameter int unsigned NumInputs = 1
) (
  input  logic [NumInputs - 1:0] selected,
  input  logic [      Width-1:0] data_in [NumInputs],
  output logic [      Width-1:0] data_out
);

  always_comb begin
    assert ($onehot0(selected));
    data_out = '0;
    for (int unsigned i = 0; i < NumInputs; i++) begin
      if (selected[i]) begin
        data_out = data_in[i];
      end
    end
  end

endmodule
