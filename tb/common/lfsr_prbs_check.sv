// Module: lfsr_prbs_check
// Autonomous PRBS31 lock checker (IEEE 802.3 Clause 49.2.12).

`timescale 1ns / 1ps

module lfsr_prbs_check
  import lfsr_prbs_pkg::*;
#(
  parameter int   DATA_W           = 64,
  parameter int   PRBS_BITS        = 31,
  parameter logic IEEE_INVERT      = 1'b1,
  parameter int   LOCK_MATCH_BYTES = 3
) (
  input wire logic clk,
  input wire logic rst,

  input  wire logic              enable,
  input  wire logic [DATA_W-1:0] data_in,
  output logic                   locked,
  output logic                   error_pulse,
  output logic      [      31:0] error_count,

  input  wire logic                clear_errors,
  input  wire logic [DATA_W/8-1:0] byte_valid = '1,
  input  wire logic                restart = 1'b0,
  input  wire logic [DATA_W/8-1:0] restart_mask = '0,
  output logic      [DATA_W/8-1:0] byte_errors
);

  // G(x) = 1 + x^28 + x^31
  localparam int BYTES_PER_WORD = DATA_W / 8;
  localparam int SEED_BYTES_REQUIRED = 4;

  typedef enum logic {
    ACQUIRE = 1'b0,
    VERIFY  = 1'b1
  } prbs_phase_t;

  typedef struct packed {
    prbs_phase_t phase;
    logic [30:0] lfsr;
    int unsigned seed_bytes;
    int unsigned matched_bytes;
    logic        locked;
  } prbs_state_t;

  prbs_state_t state_reg;
  prbs_state_t state_next;
  logic [31:0] error_count_next;

  initial begin
    if (DATA_W < 8 || DATA_W % 8 != 0 || PRBS_BITS != 31 || LOCK_MATCH_BYTES < 1) begin
      $fatal(
          1,  //
          "PRBS31 checker requires byte-aligned DATA_W, PRBS_BITS=31, and a positive lock threshold"
              );
    end
  end

  always_comb begin
    state_next       = state_reg;
    error_count_next = clear_errors ? '0 : error_count;
    byte_errors      = '0;

    if (restart) state_next = '0;

    for (int lane = 0; lane < BYTES_PER_WORD; lane++) begin
      logic [7:0] received_byte;
      logic [38:0] prediction;
      received_byte = data_in[lane*8+:8];
      prediction    = '0;

      if (restart_mask[lane]) state_next = '0;

      if (enable && byte_valid[lane]) begin
        case (state_next.phase)
          // Espera los primeros 4 bytes para poder predecir el siguiente byte,
          // el LFSR necesita 31 bits para realizar la prediccion
          ACQUIRE: begin
            state_next.lfsr       = prbs31_seed_byte(state_next.lfsr, received_byte, IEEE_INVERT);
            state_next.seed_bytes = state_next.seed_bytes + 1;
            if (state_next.seed_bytes == SEED_BYTES_REQUIRED) begin
              // Si los 31 bits son 0, error
              if (state_next.lfsr == '0) begin
                byte_errors[lane] = 1'b1;
                state_next        = '0;
              end else begin
                state_next.phase = VERIFY;
              end
            end
          end
          VERIFY: begin
            // Tenemos los 31 bits, se realiza la predicción
            prediction = prbs31_step_8b(state_next.lfsr, IEEE_INVERT);
            if (received_byte !== prediction[7:0]) begin
              byte_errors[lane]     = 1'b1;
              state_next            = '0;
              // Reset a adquire y capturamos un byte nuevo
              state_next.lfsr       = prbs31_seed_byte('0, received_byte, IEEE_INVERT);
              state_next.seed_bytes = 1;
            end else begin
              // Update de la LFSR
              state_next.lfsr = prediction[38:8];
              if (state_next.matched_bytes < LOCK_MATCH_BYTES) begin
                state_next.matched_bytes = state_next.matched_bytes + 1;
              end
              if (state_next.matched_bytes == LOCK_MATCH_BYTES) state_next.locked = 1'b1;
            end
          end
          default: state_next = '0;
        endcase
        // Si el bit no matchea con la PRBS o los 31 bits son todos 0
        if (byte_errors[lane]) error_count_next = error_count_next + 1'b1;
      end
    end
  end

  // La salida queda como registro porque ya es estable
  assign locked = state_reg.locked;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_reg   <= '{phase: ACQUIRE, default: '0};
      error_pulse <= 1'b0;
      error_count <= '0;
    end else begin
      state_reg   <= state_next;
      error_count <= error_count_next;
      error_pulse <= |byte_errors;
    end
  end

endmodule
