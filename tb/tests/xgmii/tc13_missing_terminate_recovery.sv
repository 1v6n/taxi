// Testcase: tc13_missing_terminate_recovery
//
// 1) Aplicar el reset
// 2) Enviar la secuencia de datos válida. EN y VALID siempre seteados
//    - Enviar una trama sin el símbolo /T/ final.
//    - Enviar una trama PRBS válida para comprobar la recuperación.
// 3) Verificar la salida del DUT
//    - Verificar la respuesta a la trama incompleta.
// 4) Verificar el payload de salida
//    - Verificar la recepción correcta de la trama de recuperación.
// 5) Aplicar el reset y repetir N_ITERACIONES.

`timescale 1ns / 1ps

module tc13_missing_terminate_recovery;

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
      $dumpvars(0, tc13_missing_terminate_recovery);
    end
  end

  tb_env_xgmii env (
    .clk               (clk),
    .tx_rst            (tx_rst),
    .rx_rst            (rx_rst),
    .checker_rst       (checker_rst),
    .in_frame          (in_frame),
    .frame_count       (frame_count),
    .payload_byte_count(payload_byte_count),
    .prbs_locked       (prbs_locked),
    .frame_bad         (frame_bad),
    .agent_error_count (agent_error_count),
    .clear_errors      (clear_errors)
  );

  `include "xgmii_test_helpers.svh"


  task automatic run_case;
    logic [31:0] frames_before;
    logic [31:0] bytes_before;
    reset_and_warm_up();
    send_prbs_frame(PAYLOAD_BYTES, 0, 1'b0);
    wait_for_rx_error();
    $display("[INFO] [%m] La trama sin /T/ produjo un word completo de /E/");
    wait_for_rx_frame_end();
    clear_rx_errors();
    frames_before = frame_count;
    bytes_before = payload_byte_count;
    send_prbs_frame(PAYLOAD_BYTES, 0, 1'b1);
    wait_for_rx_valid(frames_before, PAYLOAD_BYTES,
                      bytes_before);
  endtask

  initial begin
    $display("[INFO] [%m] Inicio: iteraciones=%0d payload_bytes=%0d",
             N_ITERATIONS, PAYLOAD_BYTES);

    for (int iter = 0; iter < N_ITERATIONS; iter++) begin
      $display("[INFO] [%m] Iteracion %0d/%0d", iter + 1, N_ITERATIONS);
      run_case();
    end

    $display("[PASS] [%m] Prueba completada");
    $finish;
  end

endmodule
