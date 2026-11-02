// Package: eth_phy_10g_tb_pkg
// IEEE 802.3 Clause 46 (XGMII) and Clause 49 (64B/66B PCS) definitions.

`timescale 1ns / 1ps

package eth_phy_10g_tb_pkg;

  /* verilator lint_off UNUSEDPARAM */

  // Bus Widths
  localparam int XGMII_DATA_W = 64;
  localparam int XGMII_CTRL_W = 8;
  localparam int SERDES_DATA_W = 64;
  localparam int SERDES_HDR_W = 2;
  localparam int BLOCK_W = 66;  // 64-bit payload + 2-bit sync header

  typedef struct packed {
    logic [XGMII_DATA_W-1:0] data;
    logic [XGMII_CTRL_W-1:0] ctrl;
  } xgmii_word_t;

  // IEEE 802.3 Clause 46: XGMII Control Characters
  localparam logic [7:0] CTRL_IDLE = 8'h07;  // /I/ (Idle)
  localparam logic [7:0] CTRL_START = 8'hFB;  // /S/ (Start)
  localparam logic [7:0] CTRL_TERMINATE = 8'hFD;  // /T/ (Terminate)
  localparam logic [7:0] CTRL_ERROR = 8'hFE;  // /E/ (Error)
  localparam logic [7:0] CTRL_SEQ_OS = 8'h9C;  // /Q/ (Sequence Ordered Set)
  localparam logic [7:0] CTRL_LPI = 8'h06;  // /LI/ (Low Power Idle)
  localparam logic [7:0] PREAMBLE_BYTE = 8'h55;
  localparam logic [7:0] SFD_BYTE = 8'hD5;

  // IEEE 802.3 Clause 49: 64B/66B Sync Headers
  // Transmitted LSB-first: '01' for data (2'b10) and '10' for control (2'b01).
  localparam logic [1:0] SYNC_DATA = 2'b10;
  localparam logic [1:0] SYNC_CTRL = 2'b01;
  localparam logic [1:0] SYNC_INV_00 = 2'b00;
  localparam logic [1:0] SYNC_INV_11 = 2'b11;

  // IEEE 802.3 Clause 49: Block Types (Figure 49-7 & Table 49-1)
  localparam logic [7:0] BT_CTRL = 8'h1E;  // C7 C6 C5 C4 C3 C2 C1 C0 (Control / Idle)
  localparam logic [7:0] BT_OS_4 = 8'h2D;  // D7 D6 D5 O4 C3 C2 C1 C0 (/O/ on lane 4)
  localparam logic [7:0] BT_START_4 = 8'h33;  // D7 D6 D5 S4 C3 C2 C1 C0 (/S/ on lane 4)
  localparam logic [7:0] BT_OS_0 = 8'h4B;  // C7 C6 C5 C4 O0 D1 D2 D3 (/O/ on lane 0)
  localparam logic [7:0] BT_OS_0_4 = 8'h55;  // D7 D6 D5 O4 O0 D1 D2 D3 (/O/ on lane 0 and 4)
  localparam
      logic [7:0] BT_OS_START = 8'h66;  // D7 D6 D5 S4 O0 D1 D2 D3 (/O/ on lane 0, /S/ on lane 4)
  localparam logic [7:0] BT_START_0 = 8'h78;  // D7 D6 D5 D4 D3 D2 D1 S0 (/S/ on lane 0)
  localparam logic [7:0] BT_TERM_0 = 8'h87;  // C7 C6 C5 C4 C3 C2 C1 T0 (/T/ on lane 0)
  localparam logic [7:0] BT_TERM_1 = 8'h99;  // C7 C6 C5 C4 C3 C2 T1 D0 (/T/ on lane 1)
  localparam logic [7:0] BT_TERM_2 = 8'hAA;  // C7 C6 C5 C4 C3 T2 D1 D0 (/T/ on lane 2)
  localparam logic [7:0] BT_TERM_3 = 8'hB4;  // C7 C6 C5 C4 T3 D2 D1 D0 (/T/ on lane 3)
  localparam logic [7:0] BT_TERM_4 = 8'hCC;  // C7 C6 C5 T4 D3 D2 D1 D0 (/T/ on lane 4)
  localparam logic [7:0] BT_TERM_5 = 8'hD2;  // C7 C6 T5 D4 D3 D2 D1 D0 (/T/ on lane 5)
  localparam logic [7:0] BT_TERM_6 = 8'hE1;  // C7 T6 D5 D4 D3 D2 D1 D0 (/T/ on lane 6)
  localparam logic [7:0] BT_TERM_7 = 8'hFF;  // T7 D6 D5 D4 D3 D2 D1 D0 (/T/ on lane 7)
  localparam logic [7:0] BT_RESERVED_00 = 8'h00;  // Reserved block type (Table 49-1)

  function automatic bit is_valid_sync(input logic [1:0] hdr);
    return (hdr == SYNC_DATA || hdr == SYNC_CTRL);
  endfunction

  function automatic string get_block_type_name(input logic [7:0] bt);
    case (bt)
      BT_CTRL:        return "BT_CTRL (0x1E)";
      BT_START_0:     return "BT_START_0 (0x78)";
      BT_START_4:     return "BT_START_4 (0x33)";
      BT_OS_0:        return "BT_OS_0 (0x4B)";
      BT_OS_4:        return "BT_OS_4 (0x2D)";
      BT_OS_0_4:      return "BT_OS_0_4 (0x55)";
      BT_OS_START:    return "BT_OS_START (0x66)";
      BT_TERM_0:      return "BT_TERM_0 (0x87)";
      BT_TERM_1:      return "BT_TERM_1 (0x99)";
      BT_TERM_2:      return "BT_TERM_2 (0xAA)";
      BT_TERM_3:      return "BT_TERM_3 (0xB4)";
      BT_TERM_4:      return "BT_TERM_4 (0xCC)";
      BT_TERM_5:      return "BT_TERM_5 (0xD2)";
      BT_TERM_6:      return "BT_TERM_6 (0xE1)";
      BT_TERM_7:      return "BT_TERM_7 (0xFF)";
      BT_RESERVED_00: return "BT_RESERVED (0x00)";
      default:        return $sformatf("BT_UNKNOWN (0x%02X)", bt);
    endcase
  endfunction

  /* verilator lint_on UNUSEDPARAM */

endpackage
