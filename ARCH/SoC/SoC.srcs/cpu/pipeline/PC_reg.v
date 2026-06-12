module PC_reg(
    input clk,
    input rst_n,
    input [9:0] branch_target,
    input branch_taken,
    input stall,
    output reg [9:0] PCout
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            PCout <= 10'd0;
        else if (branch_taken) begin
            if ($test$plusargs("PC_TRACE")) begin
                $display("[PC_reg] branch_taken=1 pc=0x%0h target=0x%0h", PCout, branch_target);
            end
            PCout <= branch_target;
        end
        else if (stall)
            PCout <= PCout;               // 停顿
        else
            PCout <= PCout + 10'd4;
    end
endmodule