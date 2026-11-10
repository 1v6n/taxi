// Module: xgmii_rx_agent
// Checker 2: monitors IEEE 802.3 Clause 46 XGMII RX traffic, tracks frame delimiters,
// and verifies PRBS payload byte-by-byte.

`timescale 1ns / 1ps

module xgmii_rx_agent
  import eth_phy_10g_tb_pkg::*;
#(
  parameter int DATA_W = XGMII_DATA_W,
  parameter int CTRL_W = XGMII_CTRL_W
) (
  input wire logic clk,
  input wire logic rst,

  input wire logic [DATA_W-1:0] xgmii_rxd,
  input wire logic [CTRL_W-1:0] xgmii_rxc,

  output logic        in_frame,
  output logic [31:0] frame_count,
  output logic [31:0] payload_byte_count,
  output logic        prbs_locked,
  output logic        frame_bad,
  output logic [31:0] error_count,
  output logic        full_rx_error_detected,
  output logic        partial_rx_error_detected,

  input wire logic clear_errors
);

  typedef enum logic [1:0] {
    OUTSIDE_FRAME,
    EXPECT_DATA,
    IN_FRAME,
    AFTER_TERMINATE
  } lane_state_t;

  typedef struct packed {
    lane_state_t phase;
    logic [31:0] frame_count;
    logic [31:0] payload_byte_count;
    logic [31:0] rx_error_count;
    logic        full_rx_error_detected;
    logic        partial_rx_error_detected;
  } rx_state_t;

  typedef struct packed {
    logic is_data;
    logic is_idle;
    logic is_start;
    logic is_terminate;
    logic is_error;
  } lane_symbols_t;

  lane_symbols_t symbols [CTRL_W];
  logic full_error_word;
  logic partial_error_word;

  rx_state_t state, next_state;
  logic next_frame_bad;

  logic [31:0] prbs_error_count;

  // Variables que definen mascaras para el trackeo en si de lo
  // recibido
  logic [CTRL_W-1:0] payload_byte_mask;
  logic [CTRL_W-1:0] prbs_restart_mask;
  logic [CTRL_W-1:0] accepted_start_mask;
  logic [CTRL_W-1:0] frame_error_mask;
  logic [CTRL_W-1:0] prbs_byte_errors;

  assign in_frame              = (state.phase == EXPECT_DATA) || (state.phase == IN_FRAME);
  assign frame_count           = state.frame_count;
  assign payload_byte_count    = state.payload_byte_count;
  assign full_rx_error_detected    = state.full_rx_error_detected;
  assign partial_rx_error_detected = state.partial_rx_error_detected;
  assign error_count           = state.rx_error_count + prbs_error_count;
  assign prbs_restart_mask = accepted_start_mask | frame_error_mask;

  lfsr_prbs_check #(
    .DATA_W          (DATA_W),  //
    .LOCK_MATCH_BYTES(3)        //
  ) prbs_checker (
    .clk         (clk),                //
    .rst         (rst),                //
    .enable      (1'b1),               //
    .data_in     (xgmii_rxd),          //
    .byte_valid  (payload_byte_mask),  //
    .restart     (1'b0),               //
    .restart_mask(prbs_restart_mask),  //
    .clear_errors(clear_errors),       //
    .locked      (prbs_locked),        //
    .error_pulse (),                   //
    .error_count (prbs_error_count),   //
    .byte_errors (prbs_byte_errors)    //
  );

  task automatic reset_monitor;
    state                 <= '0;
    frame_bad             <= 1'b0;
  endtask

  // Identificar el simbolo de cada lane
  always_comb begin : decode_lanes
    foreach (symbols[lane]) begin
      logic [7:0] lane_data;

      lane_data = xgmii_rxd[lane*8+:8];
      symbols[lane].is_data = (xgmii_rxc[lane] === 1'b0);
      symbols[lane].is_idle = (xgmii_rxc[lane] === 1'b1 && lane_data === CTRL_IDLE);
      symbols[lane].is_start = (xgmii_rxc[lane] === 1'b1 && lane_data === CTRL_START);
      symbols[lane].is_terminate = (xgmii_rxc[lane] === 1'b1 && lane_data === CTRL_TERMINATE);
      symbols[lane].is_error = (xgmii_rxc[lane] === 1'b1 && lane_data === CTRL_ERROR);
    end
  end

  // Clasificar la palabra completa
  always_comb begin : classify_word
    logic all_errors;
    logic any_error;

    all_errors = 1'b1;
    any_error  = 1'b0;
    foreach (symbols[lane]) begin
      all_errors = all_errors && symbols[lane].is_error;
      any_error  = any_error || symbols[lane].is_error;
    end

    full_error_word = all_errors;
    partial_error_word = any_error && !all_errors;

  end

  // Validar la secuencia y actualizar contadores y mascaras lane por lane
  always_comb begin : validate_sequence
    lane_state_t lane_state;

    next_state = state;
    next_state.rx_error_count = clear_errors ? '0 : state.rx_error_count;
    lane_state = state.phase;

    payload_byte_mask   = '0;
    accepted_start_mask = '0;

    if (full_error_word) next_state.full_rx_error_detected = 1'b1;
    if (partial_error_word) next_state.partial_rx_error_detected = 1'b1;

    foreach (symbols[lane]) begin
      logic lane_error;
      logic invalidates_frame;

      lane_error        = 1'b0;
      invalidates_frame = 1'b0;

      case (lane_state)
        OUTSIDE_FRAME: begin
          if (symbols[lane].is_start) begin
            // Comprobar la posicion y los Idles anteriores al start
            if (lane == 0 || (lane == 4 &&
                xgmii_rxc[3:0] === 4'hf && xgmii_rxd[31:0] === {4{CTRL_IDLE}})) begin
              next_state.frame_count = next_state.frame_count + 1'b1;
              accepted_start_mask[lane] = 1'b1;
              lane_state   = EXPECT_DATA;
            // Start en posicion no valida o no hay idles antes
            end else begin
              lane_error = 1'b1;
              invalidates_frame = 1'b1;
            end
          // No es start y tampoco es idle
          end else if (!symbols[lane].is_idle) begin
            lane_error = 1'b1;
            if (symbols[lane].is_terminate) lane_state = AFTER_TERMINATE;
          end
        end

        EXPECT_DATA, IN_FRAME: begin
          if (symbols[lane].is_data) begin
            next_state.payload_byte_count = next_state.payload_byte_count + 1'b1;
            payload_byte_mask[lane] = 1'b1;
            lane_state     = IN_FRAME;
          end else if (symbols[lane].is_terminate) begin
            // /T/ sin ningun dato posterior a /S/, no es valido
            if (lane_state == EXPECT_DATA) begin
              lane_error = 1'b1;
              invalidates_frame = 1'b1;
            end
            lane_state = AFTER_TERMINATE;
          end else begin
            lane_error = 1'b1;
            invalidates_frame = 1'b1;
            // /E/ marca el error, pero no termina por si mismo la recepcion
            if (!symbols[lane].is_error) lane_state = OUTSIDE_FRAME;
          end
        end

        AFTER_TERMINATE: begin
          // Esperamos que hayan idles despues del terminate
          if (!symbols[lane].is_idle) begin
            lane_error = 1'b1;
            invalidates_frame = 1'b1;
          end
        end

        default: begin
          lane_error = 1'b1;
          invalidates_frame = 1'b1;
          lane_state        = OUTSIDE_FRAME;
        end
      endcase

      if (lane_error)
        next_state.rx_error_count = next_state.rx_error_count + 1'b1;
      frame_error_mask[lane] = invalidates_frame;
    end

    // El estado de cierre solo dura hasta el final del word.
    next_state.phase = lane_state;
    if (lane_state == AFTER_TERMINATE)
      next_state.phase = OUTSIDE_FRAME;
  end

  // Decide si el frame está mal, teniendo en cuenta también los datos de la
  // PRBS
  always_comb begin : frame_result
    next_frame_bad = frame_bad;

    foreach (symbols[lane]) begin
      if (frame_error_mask[lane] || prbs_byte_errors[lane]) begin
        next_frame_bad = 1'b1;
      end else if (accepted_start_mask[lane]) begin
        next_frame_bad = 1'b0;
      end
    end
  end

  // Actualizo las salidas del agente
  always @(posedge clk or posedge rst) begin : monitor
    if (rst) begin
      reset_monitor();
    end else begin
      state                 <= next_state;
      frame_bad             <= next_frame_bad;
    end
  end

endmodule
