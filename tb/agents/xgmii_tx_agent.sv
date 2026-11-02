// Module: xgmii_tx_agent
// Generator 1: drives IEEE 802.3 Clause 46 XGMII TX traffic using a FIFO word queue

`timescale 1ns / 1ps

module xgmii_tx_agent
  import eth_phy_10g_tb_pkg::*;
  import lfsr_prbs_pkg::*;
#(
  parameter int DATA_W = XGMII_DATA_W,
  parameter int CTRL_W = XGMII_CTRL_W
) (
  input wire logic clk,
  input wire logic rst,

  output logic [DATA_W-1:0] xgmii_txd,
  output logic [CTRL_W-1:0] xgmii_txc,
  output logic              xgmii_tx_valid
);

  localparam int LANES_PER_WORD = XGMII_CTRL_W;
  localparam xgmii_word_t IDLE_WORD = '{
      data: {LANES_PER_WORD{CTRL_IDLE}},
      ctrl: {LANES_PER_WORD{1'b1}}
  };

  // FIFO dinamica
  xgmii_word_t tx_queue[$];
  logic [30:0] prbs_tx_lfsr;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      xgmii_txd      <= IDLE_WORD.data;
      xgmii_txc      <= IDLE_WORD.ctrl;
      xgmii_tx_valid <= 1'b1;
      tx_queue.delete();
      prbs_tx_lfsr <= PRBS31_DEFAULT_SEED;
      // Se hace pop de la fifo y se arrancan a enviar las palabras
    end else if (tx_queue.size() > 0) begin
      automatic xgmii_word_t word = tx_queue.pop_front();
      xgmii_txd      <= word.data;
      xgmii_txc      <= word.ctrl;
      xgmii_tx_valid <= 1'b1;
      // No hay nada en la fifo, mandamos IDLE
    end else begin
      xgmii_txd      <= IDLE_WORD.data;
      xgmii_txc      <= IDLE_WORD.ctrl;
      xgmii_tx_valid <= 1'b1;
    end
  end

  task automatic init();
    tx_queue.delete();
    prbs_tx_lfsr = PRBS31_DEFAULT_SEED;
  endtask

  task automatic push_word(input logic [DATA_W-1:0] data, input logic [CTRL_W-1:0] ctrl);
    xgmii_word_t word;
    word.data = data;
    word.ctrl = ctrl;
    tx_queue.push_back(word);
  endtask

  task automatic push_idles(input int count);
    repeat (count) tx_queue.push_back(IDLE_WORD);
  endtask

  function automatic xgmii_word_t set_byte(input xgmii_word_t word,  //
                                           input int lane,  //
                                           input logic [7:0] byte_value,  //
                                           input logic is_control  //
                                               );
    xgmii_word_t result;

    result                 = word;
    result.data[lane*8+:8] = byte_value;
    result.ctrl[lane]      = is_control;
    return result;
  endfunction

  // El frame es /S/ + PRBS + /T/
  // Legal starts use lane 0 or 4. Other lanes remain available for negative tests
  task automatic push_frame(input logic [7:0] payload[], input int start_lane = 0);
    xgmii_word_t word;
    int lane;

    // 1. /S/
    word = set_byte(IDLE_WORD, start_lane, CTRL_START, 1'b1);
    lane = start_lane + 1;

    // 2. Despues de /S/, arranca los bits de payload que corresponden a la
    // PRBS
    foreach (payload[byte_index]) begin
      if (lane == LANES_PER_WORD) begin
        tx_queue.push_back(word);
        word = IDLE_WORD;
        lane = 0;
      end

      word = set_byte(word, lane, payload[byte_index], 1'b0);
      lane = lane + 1;
    end

    // 3. Si está llena la palabra, generamos una nueva con IDLEs y reservamos
    // el lane 0 para el terminate
    if (lane == LANES_PER_WORD) begin
      tx_queue.push_back(word);
      word = IDLE_WORD;
      lane = 0;
    end

    // 4. Se coloca el /T/ al final
    word = set_byte(word, lane, CTRL_TERMINATE, 1'b1);
    tx_queue.push_back(word);
  endtask

  // Se genera el payload PRBS. Guarda los 31 bits para cuando se necesite
  // generar otro byte
  task automatic push_prbs_frame(input int num_bytes, input int start_lane = 0);
    logic [7:0] prbs_bytes[];
    logic [38:0] prbs_step;

    prbs_bytes = new[num_bytes];
    for (int i = 0; i < num_bytes; i = i + 1) begin
      prbs_step     = prbs31_step_8b(prbs_tx_lfsr);
      prbs_bytes[i] = prbs_step[7:0];
      prbs_tx_lfsr  = prbs_step[38:8];
    end
    push_frame(prbs_bytes, start_lane);
  endtask

  // Inyección de error
  task automatic inject_error(input int queue_idx, input int lane);
    if (queue_idx < tx_queue.size()) begin
      tx_queue[queue_idx].ctrl[lane]      = 1'b1;
      tx_queue[queue_idx].data[lane*8+:8] = CTRL_ERROR;
    end
  endtask

  // Espera que se vacie la queue
  task automatic wait_done();
    while (tx_queue.size() > 0) @(posedge clk);
    @(posedge clk);
  endtask

  // Mandamos el frame completo
  task automatic send_prbs_frame(input int num_bytes, input int start_lane = 0);
    push_prbs_frame(num_bytes, start_lane);
    wait_done();
  endtask

endmodule
