module Instruction_Memory(ReadAddress,Instruction);
  
input[9:0] ReadAddress;
output[31:0] Instruction;
  
reg[31:0] Instruction;
wire[7:0] InstMem[127:0];
 
// Hardcoded JALR self-test
// 0x00: addi x1, x0, 16      ; rs1 base
// 0x04: jalr x5, x1, 8       ; jump to 0x18, and x5 = 0x08
// 0x08: addi x2, x0, 1       ; should be skipped
// 0x0C: addi x3, x0, 2       ; should be skipped
// 0x10: nop
// 0x14: nop
// 0x18: addi x4, x0, 9       ; jump lands here
// 0x1C: add  x6, x5, x4      ; x6 should become 17 (8 + 9)
// 0x20: beq  x0, x0, 0       ; hold here forever
assign InstMem[0] = 8'h93,       // 0x01000093
       InstMem[1] = 8'h00,
       InstMem[2] = 8'h00,
       InstMem[3] = 8'h01;

assign InstMem[4] = 8'hE7,       // 0x008082E7
       InstMem[5] = 8'h82,
       InstMem[6] = 8'h80,
       InstMem[7] = 8'h00;

assign InstMem[8] = 8'h13,       // 0x00100113
       InstMem[9] = 8'h01,
       InstMem[10] = 8'h10,
       InstMem[11] = 8'h00;

assign InstMem[12] = 8'h93,      // 0x00200193
       InstMem[13] = 8'h01,
       InstMem[14] = 8'h20,
       InstMem[15] = 8'h00;

assign InstMem[16] = 8'h13,      // 0x00000013 (nop)
       InstMem[17] = 8'h00,
       InstMem[18] = 8'h00,
       InstMem[19] = 8'h00;

assign InstMem[20] = 8'h13,      // 0x00000013 (nop)
       InstMem[21] = 8'h00,
       InstMem[22] = 8'h00,
       InstMem[23] = 8'h00;

assign InstMem[24] = 8'h13,      // 0x00900213
       InstMem[25] = 8'h02,
       InstMem[26] = 8'h90,
       InstMem[27] = 8'h00;

assign InstMem[28] = 8'h33,      // 0x00428333
       InstMem[29] = 8'h83,
       InstMem[30] = 8'h42,
       InstMem[31] = 8'h00;

assign InstMem[32] = 8'h63,      // 0x00000063
       InstMem[33] = 8'h00,
       InstMem[34] = 8'h00,
       InstMem[35] = 8'h00;

// Rest of memory set to NOP (ADDI x0, x0, 0)
assign InstMem[36] = 8'h13,
       InstMem[37] = 8'h00,
       InstMem[38] = 8'h00,
       InstMem[39] = 8'h00;
   
                                                                                                        
always@(ReadAddress) 
  Instruction = {InstMem[ReadAddress+32'd3],InstMem[ReadAddress+32'd2],
                 InstMem[ReadAddress+32'd1],InstMem[ReadAddress]};
                   
endmodule