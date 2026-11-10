task automatic wait_cycles(input int cycles);
  repeat (cycles) begin
    @(posedge clk);
    #1ps;
  end
endtask

// Esperar la salida de la trama actual
task automatic wait_for_rx_frame_end();
  while (in_frame)
    wait_cycles(1);
endtask

// Esperar una nueva trama y verificar los resultados del agente RX
task automatic wait_for_rx_valid(
    input logic [31:0] initial_frame_count = 0,
    input int expected_payload_bytes = PAYLOAD_BYTES,
    input logic [31:0] initial_payload_byte_count = 0
);
  while (frame_count <= initial_frame_count || in_frame)
    wait_cycles(1);

  if (frame_bad)
    $fatal(1, "[ERROR] [%m] El Checker RX marco la trama como invalida");

  if (agent_error_count != 0)
    $fatal(1, "[ERROR] [%m] Errores RX: %0d", agent_error_count);

  if (frame_count != initial_frame_count + 1)
    $fatal(1, "[ERROR] [%m] Cantidad de tramas incorrecta: recibidas=%0d esperadas=%0d",
           frame_count, initial_frame_count + 1);

  if (payload_byte_count - initial_payload_byte_count != expected_payload_bytes)
    $fatal(1, "[ERROR] [%m] Payload incorrecto: bytes=%0d esperados=%0d",
           payload_byte_count - initial_payload_byte_count,
           expected_payload_bytes);

  if (!prbs_locked)
    $fatal(1, "[ERROR] [%m] La PRBS no obtuvo el lock");

endtask

// Borrar solo los contadores de errores del checker
task automatic clear_rx_errors();
  clear_errors = 1'b1;
  wait_cycles(1);
  clear_errors = 1'b0;
endtask

// Esperar una respuesta de error
task automatic wait_for_rx_error();
  while (!env.full_rx_error_detected && !env.partial_rx_error_detected)
    wait_cycles(1);
  if (env.partial_rx_error_detected)
      $fatal(1, "[ERROR] [%m] Respuesta /E/ parcial");
  else if (!env.full_rx_error_detected)
      $fatal(1, "[ERROR] [%m] No se observo un word completo de /E/");
endtask

// Enviar trama PRBS al DUT y esperar
task automatic send_prbs_frame(input int payload_bytes, input int start_lane = 0, input bit terminate = 1'b1);
  env.tx_agent.push_prbs_frame(payload_bytes, start_lane, terminate);
  env.tx_agent.wait_done();
endtask

task automatic reset_and_warm_up();
  tx_rst       = 1'b1;
  rx_rst       = 1'b1;
  checker_rst  = 1'b1;
  clear_errors = 1'b0;
  env.tx_agent.init();
  wait_cycles(2);
  tx_rst = 1'b0;
  rx_rst = 1'b0;
  send_prbs_frame(1024, 0);
  wait_cycles(10);
  checker_rst = 1'b0;
endtask
