module ALU(
   control_signal,
   read_data1,
   read_data2,
   immediate,
   ALU_src,
   ALU_result,
   ALU_zero
);
input ALU_src;
input [3:0 ] control_signal;
input [31:0] read_data1;
input [31:0] read_data2;
input [31:0] immediate;
 
output   reg  [31:0] ALU_result;
output   reg         ALU_zero  ;

reg [31:0] ALU_data2;
always @(*) begin
    if(ALU_src)
        ALU_data2 = immediate;
    else
        ALU_data2 = read_data2;
end

always @(*) begin
    case(control_signal)
        4'b0000: ALU_result = read_data1 + ALU_data2;
        4'b0001: ALU_result = read_data1 - ALU_data2;  // 减法直接使用运算符
        4'b0010: ALU_result = read_data1 & ALU_data2;
        4'b0011: ALU_result = read_data1 | ALU_data2;
        4'b0100: ALU_result = read_data1 << ALU_data2[4:0];
        4'b0101: ALU_result = read_data1 >> ALU_data2[4:0];
        4'b0110: ALU_result = (read_data1 < ALU_data2) ? 32'd1 : 32'd0;
        4'b0111: ALU_result = read_data1 ^ ALU_data2;
        4'b1100: ALU_result = ($signed(read_data1) < $signed(ALU_data2)) ? 32'd1 : 32'd0;
        4'b1010: ALU_result = $signed(read_data1) >>> ALU_data2[4:0];
        default: ALU_result = 32'd0;
    endcase
end

always @(*) begin
    case(control_signal)
        4'b1000: ALU_zero = (read_data1 == ALU_data2) ? 1'b1 : 1'b0;
        4'b1001: ALU_zero = 1'b1; // jal
        4'b1011: ALU_zero = (read_data1 != ALU_data2) ? 1'b1 : 1'b0;
        default: ALU_zero = 1'b0;
    endcase
end
endmodule