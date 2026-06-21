module IF_ID(
    input clk,
    input rst_n,
    input flush,
    input stall,
    input [31:0] instr_in,
    input [9:0] PC_in,
    output reg [31:0] instr_out,
    output reg [9:0] PC_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instr_out <= 32'd0;
            PC_out <= 10'd0;
        end else if (flush) begin
            instr_out <= 32'd0;      // 清空为NOP（可自定义为0）
            PC_out <= 10'd0;
        end else if (!stall) begin
            instr_out <= instr_in;
            PC_out <= PC_in;
        end
        // stall时保持原值
    end
endmodule