// Testcase: tc14_error_recovery
//
// 1) Aplicar el reset
//    - Poner reset = 0 tras los ciclos de reset y enviar la trama PRBS de calentamiento.
// 2) Enviar la secuencia de datos válida. EN y VALID siempre seteados
//    - Inicio: Lane 0 = /S/ (0xFB, TXC[0]=1).
//    - Datos: Transmitir 100 bytes de payload PRBS e inyectar /E/ dentro de la trama.
//    - Final: El símbolo /T/ final y los Idles de cierre.
//    - Recuperación: Enviar una trama PRBS nueva de 100 bytes sin inyección.
// 3) Verificar la salida del DUT
//    - Verificar la indicación /E/ y la continuidad de la recepción hasta el símbolo /T/ final.
//    - Verificar la recepción correcta de la trama posterior.
// 4) Verificar el payload de salida
//    - El Checker 2 detecta la caída de la PRBS en la transferencia corrupta y verifica
//      que la transferencia posterior obtenga el lock y no caiga la PRBS.
// 5) Aplicar el reset y repetir N_ITERACIONES.

`timescale 1ns / 1ps

module tc14_error_recovery;

  import eth_phy_10g_tb_pkg::*;

  localparam int N_ITERATIONS = 5;
  localparam int PAYLOAD_BYTES = 100;
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
      $dumpvars(0, tc14_error_recovery);
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
    logic [31:0] frames_before;
    logic [31:0] bytes_before;

    $display("[INFO] [%m] Inicio: iteraciones=%0d payload_bytes=%0d",  //
             N_ITERATIONS,  //
             PAYLOAD_BYTES  //
    );

    for (int iter = 0; iter < N_ITERATIONS; iter = iter + 1) begin
      $display("[INFO] [%m] Iteracion %0d/%0d", iter + 1, N_ITERATIONS);
      reset_and_warm_up();
      env.tx_agent.push_prbs_frame(PAYLOAD_BYTES, 0, 1'b1);
      env.tx_agent.set_queued_byte(5, 0, CTRL_ERROR, 1'b1);
      env.tx_agent.wait_done();
      wait_for_rx_error();
      wait_for_rx_frame_end();
      clear_rx_errors();
      frames_before = frame_count;
      bytes_before = payload_byte_count;
      send_prbs_frame(PAYLOAD_BYTES, 0);
      wait_for_rx_valid(frames_before, PAYLOAD_BYTES,
                        bytes_before);
    end

    $display("[PASS] [%m] Prueba completada");
    $finish;
  end
endmodule
