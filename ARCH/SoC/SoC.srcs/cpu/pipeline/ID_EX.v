module ID_EX(
    input clk,
    input rst_n,
    input flush,
    input stall,
    // 控制信号
    input regwrite_in,
    input [1:0] memtoreg_in,
    input memread_in,
    input memwrite_in,
    input ALUsrc_in,
    input [1:0] ALUop_in,
    input branch_in,
    input jal_in,
    input jalr_in,
    // 数据
    input [31:0] read_data1_in,
    input [31:0] read_data2_in,
    input [31:0] imm_in,
    input [4:0] rs1_in,
    input [4:0] rs2_in,
    input [4:0] rd_in,
    input [9:0] PC_in,
    input [31:0] instr_in,          // 新增：传递整个指令，用于lui和ALU控制
    // 输出
    output reg regwrite_out,
    output reg [1:0] memtoreg_out,
    output reg memread_out,
    output reg memwrite_out,
    output reg ALUsrc_out,
    output reg [1:0] ALUop_out,
    output reg branch_out,
    output reg jal_out,
    output reg jalr_out,
    output reg [31:0] read_data1_out,
    output reg [31:0] read_data2_out,
    output reg [31:0] imm_out,
    output reg [4:0] rs1_out,
    output reg [4:0] rs2_out,
    output reg [4:0] rd_out,
    output reg [9:0] PC_out,
    output reg [31:0] instr_out
);
// ID_EX.v
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            regwrite_out <= 1'b0;
            memtoreg_out <= 2'b00;
            memread_out <= 1'b0;
            memwrite_out <= 1'b0;
            ALUsrc_out <= 1'b0;
            ALUop_out <= 2'b00;
            branch_out <= 1'b0;
            jal_out <= 1'b0;
            jalr_out <= 1'b0;
            read_data1_out <= 32'd0;
            read_data2_out <= 32'd0;
            imm_out <= 32'd0;
            rs1_out <= 5'd0;
            rs2_out <= 5'd0;
            rd_out <= 5'd0;
            PC_out <= 10'd0;
            instr_out <= 32'd0;
        end else if (stall) begin
            // stall: 插入气泡（与 flush 相同效果）
            regwrite_out <= 1'b0;
            memtoreg_out <= 2'b00;
            memread_out <= 1'b0;
            memwrite_out <= 1'b0;
            ALUsrc_out <= 1'b0;
            ALUop_out <= 2'b00;
            branch_out <= 1'b0;
            jal_out <= 1'b0;
            jalr_out <= 1'b0;
            read_data1_out <= 32'd0;
            read_data2_out <= 32'd0;
            imm_out <= 32'd0;
            rs1_out <= 5'd0;
            rs2_out <= 5'd0;
            rd_out <= 5'd0;
            PC_out <= 10'd0;
            instr_out <= 32'd0;
        end else begin
            // 正常更新
            regwrite_out <= regwrite_in;
            memtoreg_out <= memtoreg_in;
            memread_out <= memread_in;
            memwrite_out <= memwrite_in;
            ALUsrc_out <= ALUsrc_in;
            ALUop_out <= ALUop_in;
            branch_out <= branch_in;
            jal_out <= jal_in;
            jalr_out <= jalr_in;
            read_data1_out <= read_data1_in;
            read_data2_out <= read_data2_in;
            imm_out <= imm_in;
            rs1_out <= rs1_in;
            rs2_out <= rs2_in;
            rd_out <= rd_in;
            PC_out <= PC_in;
            instr_out <= instr_in;
        end
    end

endmodule