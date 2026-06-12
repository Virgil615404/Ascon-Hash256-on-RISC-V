module EX_MEM(
    input clk,
    input rst_n,
    input flush,
    input stall,
    // 控制信号
    input regwrite_in,
    input [1:0] memtoreg_in,
    input memread_in,
    input memwrite_in,
    input branch_in,
    input jal_in,
    // 数据
    input [31:0] ALU_result_in,
    input [31:0] write_data_in,
    input [4:0] rd_in,
    input [9:0] PC_in,
    input [31:0] instr_in,          // 传递指令用于lui
    // 分支相关
    input branch_taken_in,
    input [9:0] branch_target_in,
    // 输出
    output reg regwrite_out,
    output reg [1:0] memtoreg_out,
    output reg memread_out,
    output reg memwrite_out,
    output reg branch_out,
    output reg jal_out,
    output reg [31:0] ALU_result_out,
    output reg [31:0] write_data_out,
    output reg [4:0] rd_out,
    output reg [9:0] PC_out,
    output reg [31:0] instr_out,
    output reg branch_taken_out,
    output reg [9:0] branch_target_out
);
    always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        regwrite_out <= 1'b0;
        memtoreg_out <= 2'b00;
        memread_out <= 1'b0;
        memwrite_out <= 1'b0;
        branch_out <= 1'b0;
        jal_out <= 1'b0;
        ALU_result_out <= 32'd0;
        write_data_out <= 32'd0;
        rd_out <= 5'd0;
        PC_out <= 10'd0;
        instr_out <= 32'd0;
        branch_taken_out <= 1'b0;
        branch_target_out <= 10'd0;
    end else if (flush) begin
        // flush 时清空控制信号
        regwrite_out <= 1'b0;
        memtoreg_out <= 2'b00;
        memread_out <= 1'b0;
        memwrite_out <= 1'b0;
        branch_out <= 1'b0;
        jal_out <= 1'b0;
        branch_taken_out <= 1'b0;
        // 数据路径可选清零（但通常保留，因为控制信号已清）
    end else if (stall) begin
        regwrite_out <= regwrite_out;
        memtoreg_out <= memtoreg_out;
        memread_out <= memread_out;
        memwrite_out <= memwrite_out;
        branch_out <= branch_out;
        jal_out <= jal_out;
        ALU_result_out <= ALU_result_out;
        write_data_out <= write_data_out;
        rd_out <= rd_out;
        PC_out <= PC_out;
        instr_out <= instr_out;
        branch_taken_out <= branch_taken_out;
        branch_target_out <= branch_target_out;
    end else begin
        // 正常更新，不受 stall 影响
        regwrite_out <= regwrite_in;
        memtoreg_out <= memtoreg_in;
        memread_out <= memread_in;
        memwrite_out <= memwrite_in;
        branch_out <= branch_in;
        jal_out <= jal_in;
        ALU_result_out <= ALU_result_in;
        write_data_out <= write_data_in;
        rd_out <= rd_in;
        PC_out <= PC_in;
        instr_out <= instr_in;
        branch_taken_out <= branch_taken_in;
        branch_target_out <= branch_target_in;
    end
end
endmodule