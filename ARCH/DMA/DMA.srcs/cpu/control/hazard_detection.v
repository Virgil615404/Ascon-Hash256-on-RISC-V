module hazard_detection(
    input [4:0] ID_rs1,
    input [4:0] ID_rs2,
    input [4:0] EX_rd,
    input EX_memread,
    output reg stall
);
    always @(*) begin
        if (EX_memread && (EX_rd != 5'd0) && (EX_rd == ID_rs1 || EX_rd == ID_rs2))
            stall = 1'b1;
        else
            stall = 1'b0;
    end
endmodule