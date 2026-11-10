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

  `include "xgmii_tx_stimulus.svh"
  `include "xgmii_tx_driver.svh"

endmodule
