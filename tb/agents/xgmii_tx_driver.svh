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

  // Espera que se vacie la queue
  task automatic wait_done();
    while (tx_queue.size() > 0) @(posedge clk);
    @(posedge clk);
  endtask
