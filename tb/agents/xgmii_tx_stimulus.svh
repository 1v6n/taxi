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
  word.data[lane*8+:8] = byte_value;
  word.ctrl[lane]      = is_control;
  return word;
endfunction

// El frame es /S/ + PRBS + /T/
task automatic push_frame(input logic [7:0] payload[], input int start_lane = 0, input bit terminate = 1'b1);
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
  if (terminate) word = set_byte(word, lane, CTRL_TERMINATE, 1'b1);
  tx_queue.push_back(word);
endtask

// Se genera el payload PRBS. Guarda los 31 bits para cuando se necesite
// generar otro byte
task automatic push_prbs_frame(input int num_bytes, input int start_lane = 0, input bit terminate = 1'b1);
  logic [7:0] prbs_bytes[];
  logic [38:0] prbs_step;

  prbs_bytes = new[num_bytes];
  for (int i = 0; i < num_bytes; i = i + 1) begin
    prbs_step     = prbs31_step_8b(prbs_tx_lfsr);
    prbs_bytes[i] = prbs_step[7:0];
    prbs_tx_lfsr  = prbs_step[38:8];
  end
  push_frame(prbs_bytes, start_lane, terminate);
endtask

// Reemplaza un byte de una word que que ya está en una cola
task automatic set_queued_byte(input int queue_idx,  //
                               input int lane,  //
                               input logic [7:0] value,  //
                               input logic is_control  //
                                   );
  tx_queue[queue_idx] =
      set_byte(tx_queue[queue_idx], lane, value, is_control);
endtask
