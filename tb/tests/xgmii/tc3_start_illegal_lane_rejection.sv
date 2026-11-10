// Testcase: tc3_start_illegal_lane_rejection
// Test Plan - Ethernet - XGMII: Test 3 (Start Illegal Lane Rejection)
//
// 1) Aplicar el reset
//    - Poner reset = 0 tras N ciclos y enviar las tramas PRBS hasta la sincronización.
// 2) Enviar la secuencia de datos válida. EN y VALID siempre seteados
//    - Caso de error: Inyectar /S/ (0xFB) en las lanes 1, 2 y 3, un caso a la vez, con TXC=1, seguido del payload PRBS y /T/.
//    - Caso de control: Enviar los Idles y una secuencia válida con /S/ en la lane 0.
// 3) Verificar la salida del DUT
//    - Con /S/ en las lanes 1, 2 o 3: el Checker 2 observa /E/ (0xFE, RXC=1) en XGMII RX.
// 4) Verificar el payload de salida
//    - El Checker 2 detecta la caída de la PRBS en las secuencias corruptas y verifica que la secuencia posterior con la lane 0 válida obtenga el lock y no caiga la PRBS.
// 5) Aplicar el reset y repetir N_ITERACIONES.
//    - Probar cada lane ilegal.
//    - Ampliación: Probar las lanes 1, 2, 3, 5, 6 y 7 con el payload PRBS
//      posterior y, por separado, con /S/ rodeado de Idles (TXC=0xFF).
//    - La respuesta RX debe ser un word completo de ocho /E/.

`timescale 1ns / 1ps

module tc3_start_illegal_lane_rejection;

  import eth_phy_10g_tb_pkg::*;

  localparam int N_ITERATIONS = 5;
  localparam int PAYLOAD_BYTES = 100;
  localparam int CLK_PERIOD_PS = 6400;  // 156.25 MHz
  localparam int ILLEGAL_LANES[6] = '{1, 2, 3, 5, 6, 7};
  localparam int RX_DRAIN_CYCLES = 20;

  parameter time WATCHDOG_TIMEOUT = 1ms;

  logic clk = 1'b0;
  logic tx_rst = 1'b1;
  logic rx_rst = 1'b1;
  logic checker_rst = 1'b1;
  logic clear_errors = 1'b0;
  logic in_frame;
  logic [31:0] frame_count;
  logic [31:0] payload_byte_count;
  logic prbs_locked;
  logic frame_bad;
  logic [31:0] agent_error_count;
  logic full_rx_error_detected;
  logic partial_rx_error_detected;
  string dump_file;

  initial begin
    forever #(CLK_PERIOD_PS / 2000.0) clk = ~clk;
  end

  initial begin
    #(WATCHDOG_TIMEOUT);
    $fatal(1, "[TIMEOUT] [%m] Se alcanzo el limite global de simulacion");
  end

  initial begin
    if ($value$plusargs("dump=%s", dump_file)) begin
      $dumpfile(dump_file);
      $dumpvars(0, tc3_start_illegal_lane_rejection);
    end
  end

  tb_env_xgmii env (
      .clk                  (clk),                    //
      .tx_rst               (tx_rst),                 //
      .rx_rst               (rx_rst),                 //
      .checker_rst          (checker_rst),            //
      .in_frame             (in_frame),               //
      .frame_count          (frame_count),            //
      .payload_byte_count   (payload_byte_count),     //
      .prbs_locked          (prbs_locked),            //
      .frame_bad            (frame_bad),              //
      .agent_error_count    (agent_error_count),      //
      .full_rx_error_detected   (full_rx_error_detected),     //
      .partial_rx_error_detected(partial_rx_error_detected),  //
      .clear_errors         (clear_errors)            //
  );

  `include "xgmii_test_helpers.svh"

  task automatic send_illegal_start(input int illegal_lane, input bit idle_only);
    // Caso de error: Inyectar /S/ en lane ilegal (1, 2, 3, 5, 6 o 7)
    if (idle_only) begin
      env.tx_agent.push_idles(1);
      env.tx_agent.set_queued_byte(0, illegal_lane, CTRL_START, 1'b1);
      env.tx_agent.wait_done();
    end else begin
      send_prbs_frame(PAYLOAD_BYTES, illegal_lane);
    end
  endtask

  task automatic run_case(input int illegal_lane, input bit idle_only);
    $display("[INFO] [%m] Caso: lane=%0d solo_idles=%0b", illegal_lane, idle_only);
    reset_and_warm_up();
    // Caso de error
    send_illegal_start(illegal_lane, idle_only);
    wait_for_rx_error();
    wait_cycles(RX_DRAIN_CYCLES);
    if (frame_count != 0 || in_frame || payload_byte_count != 0 || prbs_locked)
        $fatal(1, "[ERROR] [%m] RX acepto el inicio ilegal");
    clear_rx_errors();
    // Caso de control
    send_prbs_frame(PAYLOAD_BYTES, 0);
    wait_for_rx_valid();
  endtask

  initial begin
    $display("[INFO] [%m] Inicio: iteraciones=%0d payload_bytes=%0d casos=12",  //
             N_ITERATIONS, PAYLOAD_BYTES  //
    );
    for (int iter = 0; iter < N_ITERATIONS; iter = iter + 1) begin
      $display("[INFO] [%m] Iteracion %0d/%0d", iter + 1, N_ITERATIONS);
      foreach (ILLEGAL_LANES[lane_index]) begin
        run_case(ILLEGAL_LANES[lane_index], 1'b0);
        run_case(ILLEGAL_LANES[lane_index], 1'b1);
      end
    end

    $display("[PASS] [%m] Prueba completada");
    $finish;
  end

endmodule
