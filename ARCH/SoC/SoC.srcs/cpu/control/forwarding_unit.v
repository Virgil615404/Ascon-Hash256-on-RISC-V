module forwarding_unit(
    input [4:0] EX_rs1,
    input [4:0] EX_rs2,
    input [4:0] MEM_rd,
    input [4:0] WB_rd,
    input MEM_regwrite,
    input WB_regwrite,
    output reg [1:0] forwardA,
    output reg [1:0] forwardB
);
    always @(*) begin
        forwardA = 2'b00;
        forwardB = 2'b00;
        // 前递到ALU操作数A
        if (MEM_regwrite && (MEM_rd != 5'd0) && (MEM_rd == EX_rs1))
            forwardA = 2'b10;  // 从EX/MEM前递
        else if (WB_regwrite && (WB_rd != 5'd0) && (WB_rd == EX_rs1))
            forwardA = 2'b01;  // 从MEM/WB前递

        // 前递到ALU操作数B
        if (MEM_regwrite && (MEM_rd != 5'd0) && (MEM_rd == EX_rs2))
            forwardB = 2'b10;
        else if (WB_regwrite && (WB_rd != 5'd0) && (WB_rd == EX_rs2))
            forwardB = 2'b01;
    end
endmodule