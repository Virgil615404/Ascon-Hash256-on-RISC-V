`define V1 
`ifndef INCL_CONFIG
`define INCL_CONFIG

// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Configuration of the Ascon core (Hash only).

// UROL: Number of Ascon-p rounds per clock cycle.
// CCW: Width of the data buses.
`ifdef V1
localparam logic [3:0] UROL = 1;
localparam unsigned CCW = 32;
`elsif V2
localparam logic [3:0] UROL = 2;
localparam unsigned CCW = 32;
`elsif V3
localparam logic [3:0] UROL = 4;
localparam unsigned CCW = 32;
`elsif V4
localparam logic [3:0] UROL = 1;
localparam unsigned CCW = 64;
`elsif V5
localparam logic [3:0] UROL = 2;
localparam unsigned CCW = 64;
`elsif V6
localparam logic [3:0] UROL = 4;
localparam unsigned CCW = 64;
`endif
`ifndef V1
`ifndef V2
`ifndef V3
`ifndef V4
`ifndef V5
`ifndef V6
localparam logic [3:0] UROL = 4;
localparam unsigned CCW = 64;
`endif
`endif
`endif
`endif
`endif
`endif

localparam logic [3:0] W64 = 64 / CCW;  // Number of words in 64 bits
localparam logic [3:0] W128 = 128 / CCW;  // Number of words in 128 bits
localparam logic [3:0] W192 = 192 / CCW;  // Number of words in 192 bits

// Ascon parameters
localparam unsigned LANES = 5;
localparam unsigned ROUNDS_A = 12;
localparam unsigned ROUNDS_B = 12;

// Only Hash IV needed
localparam logic [63:0] IV_HASH = 64'h0000080100cc0002;  // ASCON-Hash256

// Ascon modes (Hash only)
typedef enum logic [3:0] {
  M_INVALID     = 0,
  M_HASH256     = 3
} mode_e;

// Interface data types (Hash only)
typedef enum logic [3:0] {
  D_INVALID = 0,
  D_MSG     = 3,  // for HASH
  D_HASH    = 5   // hash output
} data_e;

`endif  // INCL_CONFIG