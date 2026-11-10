// Testcase: tc9_terminate_lane_0
// Test Plan - Ethernet - XGMII: Test 9 (Terminate Lane 0)
//
// 1) Aplicar el reset
//    - Poner reset = 0 tras N ciclos y enviar las tramas PRBS hasta la sincronización.
// 2) Enviar la secuencia de datos válida. EN y VALID siempre seteados
//    - Inicio: Lane 0 = /S/ (0xFB, TXC=1).
//    - Datos: Transmitir el payload PRBS para terminar en la lane 7.
//    - Final: Lane 0 = /T/ (0xFD, TXC[0]=1), lanes 1-7 = Idles (0x07, TXC=1). Seguir con los Idles.
// 3) Verificar la salida del DUT
//    - El Checker 2 detecta el final en la lane 0 y no reporta caracteres /E/.
// 4) Verificar el payload de salida
//    - El Checker 2 espera el lock y verifica que no caiga la PRBS recibida.
// 5) Aplicar el reset y repetir N_ITERACIONES.

`timescale 1ns / 1ps

module tc9_terminate_lane_0;

  localparam int N_ITERATIONS = 5;
  // 95 bytes de payload provoca que /T/ esté en lane 0
  localparam int PAYLOAD_BYTES = 95;
  localparam int CLK_PERIOD_PS = 6400;  // 156.25 MHz

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
      $dumpvars(0, tc9_terminate_lane_0);
    end
  end

  tb_env_xgmii env (
    .clk               (clk),                 //
    .tx_rst            (tx_rst),              //
    .rx_rst            (rx_rst),              //
    .checker_rst       (checker_rst),         //
    .in_frame          (in_frame),            //
    .frame_count       (frame_count),         //
    .payload_byte_count(payload_byte_count),  //
    .prbs_locked       (prbs_locked),         //
    .frame_bad         (frame_bad),           //
    .agent_error_count (agent_error_count),   //
    .clear_errors      (clear_errors)         //
  );

  `include "xgmii_test_helpers.svh"

  initial begin
    $display("[INFO] [%m] Inicio: iteraciones=%0d payload_bytes=%0d",  //
             N_ITERATIONS,  //
             PAYLOAD_BYTES  //
    );

    for (int iter = 0; iter < N_ITERATIONS; iter = iter + 1) begin
      $display("[INFO] [%m] Iteracion %0d/%0d", iter + 1, N_ITERATIONS);
      reset_and_warm_up();
      send_prbs_frame(PAYLOAD_BYTES, 0);
      wait_for_rx_valid();
    end

    $display("[PASS] [%m] Prueba completada");
    $finish;
  end

endmodule
