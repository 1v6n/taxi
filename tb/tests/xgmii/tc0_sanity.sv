// Testcase: tc0_sanity
// Test Plan - Ethernet - XGMII: Test 0 (Sanity)
//
// 1) Aplicar el reset
//    - Liberar el reset y enviar los Idles durante 128 ciclos de calentamiento.
// 2) Enviar la secuencia de datos válida. EN y VALID siempre seteados
//    - Inicio: Lane 0 = /S/ (0xFB, TXC[0]=1).
//    - Datos: Transmitir 100 bytes de payload PRBS.
//    - Final: El símbolo /T/ final en la lane 5 y los Idles de cierre.
// 3) Verificar la salida del DUT
//    - El Checker 2 verifica la calificación XGMII y la ausencia de errores.
//    - Verificar una trama completa y exactamente 100 bytes de payload.
// 4) Verificar el payload de salida
//    - El Checker 2 espera el lock y verifica que no caiga la PRBS recibida.
// 5) Aplicar el reset y repetir N_ITERACIONES.

`timescale 1ns / 1ps

module tc0_sanity;

  localparam int N_ITERATIONS = 5;
  localparam int PAYLOAD_BYTES = 100;
  localparam int IDLE_WARMUP_CYCLES = 128;
  localparam int CLK_PERIOD_PS = 6400;  // 156.25 MHz

  logic clk = 1'b0;
  initial begin
    forever #(CLK_PERIOD_PS / 2000.0) clk = ~clk;
  end

  logic tx_rst = 1'b1;
  logic rx_rst = 1'b1;
  logic clear_errors = 1'b0;

  logic in_frame;
  logic [31:0] frame_count;
  logic [31:0] payload_byte_count;
  logic prbs_locked;
  logic frame_bad;
  logic [31:0] agent_error_count;

  tb_env_xgmii env (
    .clk               (clk),                 //
    .tx_rst            (tx_rst),              //
    .rx_rst            (rx_rst),              //
    .in_frame          (in_frame),            //
    .frame_count       (frame_count),         //
    .payload_byte_count(payload_byte_count),  //
    .prbs_locked       (prbs_locked),         //
    .frame_bad         (frame_bad),           //
    .agent_error_count (agent_error_count),   //
    .clear_errors      (clear_errors)         //
  );

  initial begin
    #1ms;
    $fatal(1, "[TIMEOUT] Global simulation watchdog triggered.");
  end

  string dump_file;

  task automatic reset_and_warm_up;
    tx_rst = 1'b1;
    rx_rst = 1'b1;
    env.tx_agent.init();
    repeat (10) @(posedge clk);
    @(posedge clk);
    tx_rst = 1'b0;
    rx_rst = 1'b0;

    //Mandamos 128 ciclos de IDLE para que haya block_lock. Unicamente
    //necesitamos 64 bloques
    repeat (IDLE_WARMUP_CYCLES) @(posedge clk);
  endtask

  task automatic send_and_wait_frame;
    fork
      begin : send_frame
        env.tx_agent.send_prbs_frame(PAYLOAD_BYTES);
      end
      begin : wait_for_received_frame
        while (frame_count == 0 || in_frame) begin
          @(posedge clk);
          #1ps;
        end
      end
    join

    repeat (20) @(posedge clk);
  endtask

  task automatic check_result;
    if (frame_bad) begin
      $fatal(1,  //
             "[ERROR] Checker 2 marco la transferencia como invalida"  //
      );
    end
    if (agent_error_count != 0) begin
      $fatal(1,  //
             "[ERROR] Checker 2 detecto errores en recepcion: error_count = %0d",  //
             agent_error_count  //
      );
    end
    if (frame_count != 1 || in_frame || payload_byte_count != PAYLOAD_BYTES) begin
      $fatal(1,  //
             {"[ERROR] Trama incorrecta: tramas=%0d bytes=%0d ",
              "esperadas=%0d bytes esperados=%0d trama abierta=%0b"}, frame_count,  //
             payload_byte_count,  //
             1,  //
             PAYLOAD_BYTES,  //
             in_frame  //
      );
    end

    if (!prbs_locked) begin
      $fatal(1, "[ERROR] PRBS no engancho (prbs_locked == 0)");
    end
  endtask

  initial begin
    if ($value$plusargs("dump=%s", dump_file)) begin
      $dumpfile(dump_file);
      $dumpvars(0, tc0_sanity);
    end

    $display("Sanity: %0d iteraciones, %0d bytes PRBS",  //
             N_ITERATIONS,  //
             PAYLOAD_BYTES  //
    );

    for (int iter = 0; iter < N_ITERATIONS; iter = iter + 1) begin
      $display("Iteracion %0d/%0d", iter + 1, N_ITERATIONS);
      reset_and_warm_up();
      send_and_wait_frame();
      check_result();
    end

    $display("PASS: sanity");
    $finish;
  end

endmodule
