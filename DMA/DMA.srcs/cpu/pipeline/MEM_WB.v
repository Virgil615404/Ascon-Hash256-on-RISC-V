module MEM_WB(
    input clk,
    input rst_n,
    input flush,
    input stall,
    input regwrite_in,
    input [1:0] memtoreg_in,
    input jal_in,
    input [31:0] mem_data_in,
    input [31:0] alu_result_in,
    input [4:0] rd_in,
    input [9:0] PC_in,
    input [31:0] instr_in,          // 新增
    output reg regwrite_out,
    output reg [1:0] memtoreg_out,
    output reg jal_out,
    output reg [31:0] mem_data_out,
    output reg [31:0] alu_result_out,
    output reg [4:0] rd_out,
    output reg [9:0] PC_out,
    output reg [31:0] instr_out
);
    always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        regwrite_out <= 1'b0;
        memtoreg_out <= 2'b00;
        jal_out <= 1'b0;
        mem_data_out <= 32'd0;
        alu_result_out <= 32'd0;
        rd_out <= 5'd0;
        PC_out <= 10'd0;
        instr_out <= 32'd0;
    end else if (flush) begin
        regwrite_out <= 1'b0;
        memtoreg_out <= 2'b00;
        jal_out <= 1'b0;
    end else if (stall) begin
        regwrite_out <= regwrite_out;
        memtoreg_out <= memtoreg_out;
        jal_out <= jal_out;
        mem_data_out <= mem_data_out;
        alu_result_out <= alu_result_out;
        rd_out <= rd_out;
        PC_out <= PC_out;
        instr_out <= instr_out;
    end else begin
        regwrite_out <= regwrite_in;
        memtoreg_out <= memtoreg_in;
        jal_out <= jal_in;
        mem_data_out <= mem_data_in;
        alu_result_out <= alu_result_in;
        rd_out <= rd_in;
        PC_out <= PC_in;
        instr_out <= instr_in;
    end
end
endmodule