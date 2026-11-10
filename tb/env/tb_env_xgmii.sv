// Module: tb_env_xgmii
// Testbench environment for XGMII Clause 46 verification with SerDes loopback.

`timescale 1ns / 1ps

module tb_env_xgmii
  import eth_phy_10g_tb_pkg::*;
  import lfsr_prbs_pkg::*;
#(
  parameter int   DATA_W              = XGMII_DATA_W,
  parameter int   CTRL_W              = XGMII_CTRL_W,
  parameter int   HDR_W               = 2,
  parameter logic BIT_REVERSE         = 1'b0,
  parameter logic SCRAMBLER_DISABLE   = 1'b0,
  parameter logic PRBS31_EN           = 1'b0,
  parameter int   TX_SERDES_PIPELINE  = 0,
  parameter int   RX_SERDES_PIPELINE  = 0,
  //Default
  parameter int   BITSLIP_HIGH_CYCLES = 1,
  parameter int   BITSLIP_LOW_CYCLES  = 7,
  parameter real  COUNT_125US         = 125000 / 6.4
) (
  input wire logic clk,
  input wire logic tx_rst,
  input wire logic rx_rst,
  input wire logic checker_rst,

  // Status de agentes

  output logic        in_frame,
  output logic [31:0] frame_count,
  output logic [31:0] payload_byte_count,
  output logic        prbs_locked,
  output logic        frame_bad,
  output logic [31:0] agent_error_count,
  output logic        full_rx_error_detected,
  output logic        partial_rx_error_detected,

  input wire logic clear_errors
);

  // XGMII
  logic [DATA_W-1:0] xgmii_txd;
  logic [CTRL_W-1:0] xgmii_txc;
  logic xgmii_tx_valid;

  logic [DATA_W-1:0] xgmii_rxd;
  logic [CTRL_W-1:0] xgmii_rxc;
  logic xgmii_rx_valid;

  // SERDES
  logic [DATA_W-1:0] serdes_tx_data;
  logic serdes_tx_data_valid;
  logic [HDR_W-1:0] serdes_tx_hdr;
  logic serdes_tx_hdr_valid;

  logic [DATA_W-1:0] serdes_rx_data;
  logic serdes_rx_data_valid;
  logic [HDR_W-1:0] serdes_rx_hdr;
  logic serdes_rx_hdr_valid;

  // SerDes loopback
  assign serdes_rx_data       = serdes_tx_data;
  assign serdes_rx_data_valid = serdes_tx_data_valid;
  assign serdes_rx_hdr        = serdes_tx_hdr;
  assign serdes_rx_hdr_valid  = serdes_tx_hdr_valid;

  // Gen 1: XGMII TX Agent
  xgmii_tx_agent #(
    .DATA_W(DATA_W),  //
    .CTRL_W(CTRL_W)   //
  ) tx_agent (
    .clk           (clk),            //
    .rst           (tx_rst),         //
    .xgmii_txd     (xgmii_txd),      //
    .xgmii_txc     (xgmii_txc),      //
    .xgmii_tx_valid(xgmii_tx_valid)  //
  );

  // Checker 2: XGMII RX Agent
  xgmii_rx_agent #(
    .DATA_W(DATA_W),  //
    .CTRL_W(CTRL_W)   //
  ) rx_agent (
    .clk                  (clk),                    //
    .rst                  (rx_rst | checker_rst),   //
    .xgmii_rxd            (xgmii_rxd),              //
    .xgmii_rxc            (xgmii_rxc),              //
    .in_frame             (in_frame),               //
    .frame_count          (frame_count),            //
    .payload_byte_count   (payload_byte_count),     //
    .prbs_locked          (prbs_locked),            //
    .frame_bad            (frame_bad),              //
    .error_count          (agent_error_count),      //
    .full_rx_error_detected   (full_rx_error_detected),     //
    .partial_rx_error_detected(partial_rx_error_detected),  //
    .clear_errors         (clear_errors)            //
  );

  // DUT: 10G Ethernet PHY
  taxi_eth_phy_10g #(
    .DATA_W             (DATA_W),               //
    .CTRL_W             (CTRL_W),               //
    .HDR_W              (HDR_W),                //
    .TX_GBX_IF_EN       (1'b0),                 //
    .RX_GBX_IF_EN       (1'b0),                 //
    .BIT_REVERSE        (BIT_REVERSE),          //
    .SCRAMBLER_DISABLE  (SCRAMBLER_DISABLE),    //
    .PRBS31_EN          (PRBS31_EN),            //
    .TX_SERDES_PIPELINE (TX_SERDES_PIPELINE),   //
    .RX_SERDES_PIPELINE (RX_SERDES_PIPELINE),   //
    .BITSLIP_HIGH_CYCLES(BITSLIP_HIGH_CYCLES),  //
    .BITSLIP_LOW_CYCLES (BITSLIP_LOW_CYCLES),   //
    .COUNT_125US        (COUNT_125US)           //
  ) dut (
    .rx_clk                 (clk),                   //
    .rx_rst                 (rx_rst),                //
    .tx_clk                 (clk),                   //
    .tx_rst                 (tx_rst),                //
    .xgmii_txd              (xgmii_txd),             //
    .xgmii_txc              (xgmii_txc),             //
    .xgmii_tx_valid         (xgmii_tx_valid),        //
    .xgmii_rxd              (xgmii_rxd),             //
    .xgmii_rxc              (xgmii_rxc),             //
    .xgmii_rx_valid         (xgmii_rx_valid),        //
    .tx_gbx_req_sync        (),                      //
    .tx_gbx_req_stall       (),                      //
    .tx_gbx_sync            (1'b0),                  //
    .rx_gbx_sync            (),                      //
    .serdes_tx_data         (serdes_tx_data),        //
    .serdes_tx_data_valid   (serdes_tx_data_valid),  //
    .serdes_tx_hdr          (serdes_tx_hdr),         //
    .serdes_tx_hdr_valid    (serdes_tx_hdr_valid),   //
    .serdes_tx_gbx_req_sync (1'b0),                  //
    .serdes_tx_gbx_req_stall(1'b0),                  //
    .serdes_tx_gbx_sync     (),                      //
    .serdes_rx_data         (serdes_rx_data),        //
    .serdes_rx_data_valid   (serdes_rx_data_valid),  //
    .serdes_rx_hdr          (serdes_rx_hdr),         //
    .serdes_rx_hdr_valid    (serdes_rx_hdr_valid),   //
    .serdes_rx_gbx_sync     (1'b0),                  //
    .serdes_rx_bitslip      (),                      //
    .serdes_rx_reset_req    (),                      //
    .tx_bad_block           (),                      //
    .rx_error_count         (),                      //
    .rx_bad_block           (),                      //
    .rx_sequence_error      (),                      //
    .rx_block_lock          (),                      //
    .rx_high_ber            (),                      //
    .rx_status              (),                      //
    .cfg_tx_prbs31_enable   (1'b0),                  //
    .cfg_rx_prbs31_enable   (1'b0)                   //
  );

endmodule
