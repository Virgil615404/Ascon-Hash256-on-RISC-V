module control(
    input [6:0] instruction,
    output reg branch,
    output reg memread,
    output reg [1:0] memtoreg,
    output reg [1:0] ALUop,
    output reg memwrite,
    output reg ALUsrc,
    output reg regwrite,
    output reg jal,
    output reg jalr     // 新增
);
always @(*) begin
    case(instruction[6:0])
        7'b0110011: begin // R-type
            branch = 1'b0;
            memread = 1'b0;
            memtoreg = 2'b00;
            ALUop = 2'b11;
            memwrite = 1'b0;
            ALUsrc = 1'b0;
            regwrite = 1'b1;
            jal = 1'b0;
            jalr = 1'b0;
        end
        7'b0010011: begin // I-type (ALU)
            branch = 1'b0;
            memread = 1'b0;
            memtoreg = 2'b00;
            ALUop = 2'b10;
            memwrite = 1'b0;
            ALUsrc = 1'b1;
            regwrite = 1'b1;
            jal = 1'b0;
            jalr = 1'b0;
        end
        7'b0010111: begin // auipc
            branch = 1'b0;
            memread = 1'b0;
            memtoreg = 2'b11;
            ALUop = 2'b10;
            memwrite = 1'b0;
            ALUsrc = 1'b1;
            regwrite = 1'b1;
            jal = 1'b0;
            jalr = 1'b0;
        end
        7'b0000011: begin // lw
            branch = 1'b0;
            memread = 1'b1;
            memtoreg = 2'b01;
            ALUop = 2'b10;
            memwrite = 1'b0;
            ALUsrc = 1'b1;
            regwrite = 1'b1;
            jal = 1'b0;
            jalr = 1'b0;
        end
        7'b0100011: begin // sw
            branch = 1'b0;
            memread = 1'b0;
            memtoreg = 2'b00;
            ALUop = 2'b10;
            memwrite = 1'b1;
            ALUsrc = 1'b1;
            regwrite = 1'b0;
            jal = 1'b0;
            jalr = 1'b0;
        end
        7'b1100011: begin // B-type
            branch = 1'b1;
            memread = 1'b0;
            memtoreg = 2'b00;
            ALUop = 2'b01;
            memwrite = 1'b0;
            ALUsrc = 1'b0;  // 使用寄存器值比较
            regwrite = 1'b0;
            jal = 1'b0;
            jalr = 1'b0;
        end
        7'b0110111: begin // lui
            branch = 1'b0;
            memread = 1'b0;
            memtoreg = 2'b11;
            ALUop = 2'b00;   // 任意，但避免x
            memwrite = 1'b0;
            ALUsrc = 1'b0;
            regwrite = 1'b1;
            jal = 1'b0;
            jalr = 1'b0;
        end
        7'b1101111: begin // jal
            branch = 1'b1;   // 用于跳转判断
            memread = 1'b0;
            memtoreg = 2'b10;
            ALUop = 2'b00;
            memwrite = 1'b0;
            ALUsrc = 1'b0;
            regwrite = 1'b1;
            jal = 1'b1;
            jalr = 1'b0;
        end
        7'b1100111: begin // jalr
            branch = 1'b1;     // 需要跳转
            memread = 1'b0;
            memtoreg = 2'b10;  // 写回 PC+4
            ALUop = 2'b10;     // I-type ALU操作（加法）
            memwrite = 1'b0;
            ALUsrc = 1'b1;     // 使用立即数
            regwrite = 1'b1;   // 写回寄存器
            jal = 1'b1;        // 写回 PC+4
            jalr = 1'b1;       // 标记是 jalr
        end
        default: begin
            branch = 1'b0;
            memread = 1'b0;
            memtoreg = 2'b00;
            ALUop = 2'b00;
            memwrite = 1'b0;
            ALUsrc = 1'b0;
            regwrite = 1'b0;
            jal = 1'b0;
            jalr = 1'b0;
        end
    endcase
end
endmodule