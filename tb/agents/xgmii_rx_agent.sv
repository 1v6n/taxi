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
  input wire logic              xgmii_rx_valid,

  output logic        in_frame,
  output logic [31:0] frame_count,
  output logic [31:0] payload_byte_count,
  output logic        prbs_locked,
  output logic        frame_bad,
  output logic [31:0] error_count,

  input wire logic clear_errors
);

  logic next_in_frame;
  logic next_frame_bad;

  logic [31:0] next_frame_count;
  logic [31:0] rx_error_count;
  logic [31:0] next_rx_error_count;
  logic [31:0] next_payload_byte_count;

  logic [31:0] prbs_error_count;

  // Variables que definen mascaras para el trackeo en si de lo
  // recibido
  logic [CTRL_W-1:0] payload_byte_mask;
  logic [CTRL_W-1:0] prbs_restart_mask;
  logic [CTRL_W-1:0] accepted_start_mask;
  logic [CTRL_W-1:0] frame_error_mask;
  logic [CTRL_W-1:0] prbs_byte_errors;
  logic rx_valid_error;

  assign error_count = rx_error_count + prbs_error_count;

  lfsr_prbs_check #(
    .DATA_W          (DATA_W),  //
    .DEFAULT_SEED    (31'h0),   //
    .LOCK_MATCH_BYTES(3)        //
  ) prbs_checker (
    .clk         (clk),                //
    .rst         (rst),                //
    .enable      (1'b1),               //
    .data_in     (xgmii_rxd),          //
    .byte_valid  (payload_byte_mask),  //
    .restart     (rx_valid_error),     //
    .restart_mask(prbs_restart_mask),  //
    .clear_errors(clear_errors),       //
    .locked      (prbs_locked),        //
    .error_pulse (),                   //
    .error_count (prbs_error_count),   //
    .byte_errors (prbs_byte_errors)    //
  );

  task automatic reset_monitor;
    in_frame           <= 1'b0;
    frame_count        <= '0;
    rx_error_count     <= '0;
    payload_byte_count <= '0;
    frame_bad          <= 1'b0;
  endtask

  // Funcion que define si un /S/ fue correctamente colocado
  function automatic logic is_valid_start(input int lane, input logic frame_open);
    logic start_allowed;

    start_allowed = !frame_open && (lane == 0 || lane == 4) && xgmii_rx_valid;

    if (start_allowed !== 1'b1) begin
      return 1'b0;
    end

    // Si los bits anteriores al start no son IDLE, error
    if (lane == 4 && (xgmii_rxc[3:0] != 4'hf || xgmii_rxd[31:0] != {4{CTRL_IDLE}})) begin
      return 1'b0;
    end

    return 1'b1;
  endfunction

  // Se uso un bloque combinacional para que el decode se haga en el mismo
  // ciclo, así RX y la PRBS pueden samplear la misma palabra
  always_comb begin : decode_word
    logic start_on_lane0;
    logic start_on_lane4;
    logic terminate_seen;

    next_in_frame           = in_frame;
    next_frame_count        = frame_count;
    next_rx_error_count     = clear_errors ? '0 : rx_error_count;
    next_payload_byte_count = payload_byte_count;

    // Mascaras para la actual palabra
    payload_byte_mask       = '0;
    prbs_restart_mask       = '0;
    accepted_start_mask     = '0;
    frame_error_mask        = '0;
    rx_valid_error          = 1'b0;
    terminate_seen          = 1'b0;

    // Verifico que en la palabra actual se haya usado un /S/ de forma
    // correcta
    start_on_lane0          = xgmii_rxc[0] && xgmii_rxd[7:0] == CTRL_START;
    start_on_lane4          = xgmii_rxc[4] && xgmii_rxd[39:32] == CTRL_START;

    if (xgmii_rx_valid !== 1'b1 && (next_in_frame || start_on_lane0 || start_on_lane4)) begin
      rx_valid_error      = 1'b1;
      next_rx_error_count = next_rx_error_count + 1'b1;
    end

    // For que va lane por lane revisando los byte de control
    for (int lane = 0; lane < CTRL_W; lane = lane + 1) begin
      logic [7:0] lane_data;
      logic lane_error;
      logic invalidates_frame;

      lane_data         = xgmii_rxd[lane*8+:8];
      lane_error        = 1'b0;
      invalidates_frame = 1'b0;

      if (xgmii_rxc[lane]) begin

        case (lane_data)
          CTRL_START: begin
            // Si es un /S/
            if (is_valid_start(lane, next_in_frame)) begin
              next_in_frame             = 1'b1;
              next_frame_count          = next_frame_count + 1'b1;
              accepted_start_mask[lane] = 1'b1;
              prbs_restart_mask[lane]   = 1'b1;
            end else begin
              lane_error        = 1'b1;
              invalidates_frame = 1'b1;
            end
          end

          CTRL_TERMINATE: begin
            // Si es un /T/
            terminate_seen = 1'b1;
            if (next_in_frame) begin
              next_in_frame = 1'b0;
            end else begin
              lane_error = 1'b1;
            end
          end

          CTRL_ERROR: begin
            // Si es /E/
            lane_error = 1'b1;
            if (next_in_frame) begin
              invalidates_frame = 1'b1;
            end
          end

          default: begin
            // Si es control y no pertenece a la norma
            if (next_in_frame) begin
              lane_error        = 1'b1;
              invalidates_frame = 1'b1;
            end
          end
        endcase
        //Es dato, nos interesan solo los datos que llegan con valid
      end else if (next_in_frame) begin
        next_payload_byte_count = next_payload_byte_count + 1'b1;
        payload_byte_mask[lane] = (xgmii_rx_valid === 1'b1);
      end else if (terminate_seen) begin
        // Dato después de un terminate, es invalido
        lane_error        = 1'b1;
        invalidates_frame = 1'b1;
      end

      if (lane_error) begin
        next_rx_error_count = next_rx_error_count + 1'b1;
      end
      if (invalidates_frame) begin
        frame_error_mask[lane]  = 1'b1;
        prbs_restart_mask[lane] = 1'b1;
      end
    end
  end

  // Decide si el frame está mal, teniendo en cuenta también los datos de la
  // PRBS
  always_comb begin : frame_result
    next_frame_bad = frame_bad;

    if (rx_valid_error) begin
      next_frame_bad = 1'b1;
    end

    for (int lane = 0; lane < CTRL_W; lane++) begin
      if (accepted_start_mask[lane]) begin
        next_frame_bad = 1'b0;
      end

      if (frame_error_mask[lane] || prbs_byte_errors[lane]) begin
        next_frame_bad = 1'b1;
      end
    end
  end

  // Actualizo las salidas del agente
  always @(posedge clk or posedge rst) begin : monitor
    if (rst) begin
      reset_monitor();
    end else begin
      in_frame           <= next_in_frame;
      frame_count        <= next_frame_count;
      rx_error_count     <= next_rx_error_count;
      payload_byte_count <= next_payload_byte_count;
      frame_bad          <= next_frame_bad;
    end
  end

  task automatic wait_for_frame_start();
    while (!in_frame) @(posedge clk);
  endtask

  task automatic wait_for_frame_end();
    while (in_frame) @(posedge clk);
  endtask

endmodule
