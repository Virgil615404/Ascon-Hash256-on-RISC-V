`ifndef INCL_FUNCTIONS
`define INCL_FUNCTIONS

`include "config.sv"

function automatic logic [CCW-1:0] pad;
  localparam int BYTES = CCW / 8;
  input logic [CCW-1:0] in;
  input logic [BYTES-1:0] val;
  pad[7:0] = val[0] ? in[7:0] : 8'h00;
  for (int i = 1; i < BYTES; i += 1) begin
    pad[i*8+:8] = val[i] ? in[i*8+:8] : (val[i-1] ? 8'h01 : 8'h00);
  end
endfunction

`endif