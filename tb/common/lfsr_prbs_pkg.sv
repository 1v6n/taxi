// Package: lfsr_prbs_pkg
// Software verification models and utilities for PRBS31 (IEEE 802.3 Clause 49.2.8).

`timescale 1ns / 1ps

package lfsr_prbs_pkg;

  localparam int PRBS31_BITS = 31;
  localparam logic [PRBS31_BITS-1:0] PRBS31_DEFAULT_SEED = 31'h7FFFFFFF;

  // Avanza la LFSR de a 1 byte, devuelve el estado en 38:8 y el bit predicho
  // en 7:0. Sabemos el estado, generamos un bit en base a tal estado
  function automatic logic [38:0] prbs31_step_8b(input logic [30:0] state_in,  //
                                                 input logic invert = 1'b1  //
                                                     );
    logic [7:0] out_byte;
    logic [30:0] state;
    logic fb;

    state = state_in;
    for (int i = 0; i < 8; i = i + 1) begin
      fb          = state[30] ^ state[27];
      out_byte[i] = invert ? ~fb : fb;
      state       = {state[29:0], fb};
    end
    return {state, out_byte};
  endfunction

  // No sabemos el estado, como en RX, entonces guardamos 31 bits que se
  // insertan bit a bit en state, siguiendo el orden LSB
  function automatic logic [30:0] prbs31_seed_byte(input logic [30:0] state_in,  //
                                                   input logic [7:0] in_byte,  //
                                                   input logic invert = 1'b1  //
                                                       );
    logic [30:0] state;
    logic fb;

    state = state_in;
    for (int i = 0; i < 8; i = i + 1) begin
      fb    = invert ? ~in_byte[i] : in_byte[i];
      state = {state[29:0], fb};
    end
    return state;
  endfunction

endpackage
