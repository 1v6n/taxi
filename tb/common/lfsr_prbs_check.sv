// Module: lfsr_prbs_check
// Autonomous PRBS31 lock checker (IEEE 802.3 Clause 49.2.12).

`timescale 1ns / 1ps

module lfsr_prbs_check #(
  parameter int                   DATA_W       = 64,
  parameter int                   PRBS_BITS    = 31,
  parameter logic [PRBS_BITS-1:0] DEFAULT_SEED = {PRBS_BITS{1'b1}},
  parameter logic                 IEEE_INVERT  = 1'b1
) (
  input wire logic clk,
  input wire logic rst,

  input  wire logic              enable,
  input  wire logic [DATA_W-1:0] data_in,
  output logic                   locked,
  output logic                   error_pulse,
  output logic      [      31:0] error_count,

  input wire logic clear_errors
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

  // Seed state with the first 31 bits, then step through remaining bits
  function automatic logic [PRBS_BITS-1:0] prbs31_acquire(input logic [DATA_W-1:0] in);
    logic [PRBS_BITS-1:0] state;
    logic fb;

    state = '0;
    for (int i = 0; i < PRBS_BITS; i = i + 1) begin
      fb    = IEEE_INVERT ? ~in[i] : in[i];
      state = {state[29:0], fb};
    end
    for (int i = PRBS_BITS; i < DATA_W; i = i + 1) begin
      fb    = state[30] ^ state[27];
      state = {state[29:0], fb};
    end
    return state;
  endfunction

  typedef enum logic [1:0] {
    STATE_IDLE    = 2'b00,
    STATE_ACQUIRE = 2'b01,
    STATE_LOCKED  = 2'b10
  } state_t;

  state_t state_reg;
  logic [PRBS_BITS-1:0] lfsr_reg;
  logic [DATA_W+PRBS_BITS-1:0] lfsr_next;
  logic [DATA_W-1:0] expected_data;

  assign lfsr_next     = prbs31_step(lfsr_reg);
  assign expected_data = lfsr_next[DATA_W-1:0];

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_reg   <= STATE_IDLE;
      lfsr_reg    <= DEFAULT_SEED;
      locked      <= 1'b0;
      error_pulse <= 1'b0;
      error_count <= '0;
    end else begin
      if (clear_errors) begin
        error_count <= '0;
      end

      error_pulse <= 1'b0;

      if (!enable) begin
        state_reg <= STATE_IDLE;
        locked    <= 1'b0;
      end else begin
        case (state_reg)
          STATE_IDLE: begin
            lfsr_reg  <= prbs31_acquire(data_in);
            locked    <= 1'b0;
            state_reg <= STATE_ACQUIRE;
          end

          STATE_ACQUIRE: begin
            if (data_in == expected_data) begin
              lfsr_reg  <= lfsr_next[DATA_W+PRBS_BITS-1:DATA_W];
              locked    <= 1'b1;
              state_reg <= STATE_LOCKED;
            end else begin
              lfsr_reg  <= prbs31_acquire(data_in);
              locked    <= 1'b0;
              state_reg <= STATE_ACQUIRE;
            end
          end

          STATE_LOCKED: begin
            if (data_in != expected_data) begin
              error_pulse <= 1'b1;
              error_count <= error_count + 1;
              locked      <= 1'b0;
              lfsr_reg    <= prbs31_acquire(data_in);
              state_reg   <= STATE_ACQUIRE;
            end else begin
              lfsr_reg <= lfsr_next[DATA_W+PRBS_BITS-1:DATA_W];
              locked   <= 1'b1;
            end
          end

          default: begin
            state_reg <= STATE_IDLE;
          end
        endcase
      end
    end
  end

endmodule
