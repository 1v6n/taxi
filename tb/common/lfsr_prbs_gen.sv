// Module: lfsr_prbs_gen
// PRBS31 generator (IEEE 802.3 Clause 49.2.8).

`timescale 1ns / 1ps

module lfsr_prbs_gen #(
  parameter int                   DATA_W       = 64,
  parameter int                   PRBS_BITS    = 31,
  parameter logic [PRBS_BITS-1:0] DEFAULT_SEED = {PRBS_BITS{1'b1}},
  parameter logic                 IEEE_INVERT  = 1'b1
) (
  input wire logic clk,
  input wire logic rst,

  input  wire logic              enable,
  output logic      [DATA_W-1:0] data_out
);

  // G(x) = 1 + x^28 + x^31
  function automatic logic [DATA_W+PRBS_BITS-1:0] prbs31_step(input logic [PRBS_BITS-1:0] state_in);
    logic [DATA_W-1:0] out_data;
    logic [PRBS_BITS-1:0] state;
    logic fb;

    state = state_in;
    for (int i = 0; i < DATA_W; i = i + 1) begin
      fb          = state[30] ^ state[27];
      out_data[i] = IEEE_INVERT ? ~fb : fb;
      state       = {state[29:0], fb};
    end
    return {state, out_data};
  endfunction

  logic [PRBS_BITS-1:0] state_reg;
  logic [DATA_W+PRBS_BITS-1:0] state_next;

  assign state_next = prbs31_step(state_reg);

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_reg <= DEFAULT_SEED;
      data_out  <= '0;
    end else if (enable) begin
      state_reg <= state_next[DATA_W+PRBS_BITS-1:DATA_W];
      data_out  <= state_next[DATA_W-1:0];
    end
  end

endmodule
