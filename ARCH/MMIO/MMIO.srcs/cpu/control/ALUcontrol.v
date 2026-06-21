module ALUcontrol(
    input [1:0] ALUop,
    input [31:0] instruction,
    output reg [3:0] control_signal
);
always @(*) begin
    case (ALUop)
        2'b00: control_signal = 4'b1001; // jal
        2'b01: case (instruction[14:12])
            3'b000: control_signal = 4'b1000; // beq
            3'b001: control_signal = 4'b1011; // bne
            3'b100: control_signal = 4'b1100; // blt (slt)
            3'b101: control_signal = 4'b1101; // bge
            3'b110: control_signal = 4'b0110; // bltu (sltu)
            3'b111: control_signal = 4'b1110; // bgeu
            default: control_signal = 4'b0000;
        endcase
        2'b10: begin
            if ((instruction[6:0] == 7'b0000011) || (instruction[6:0] == 7'b0100011)) begin
                control_signal = 4'b0000; // Load/Store address calculation is always ADD
            end else begin
                case (instruction[14:12])
                    3'b000: control_signal = 4'b0000; // addi
                    3'b100: control_signal = 4'b0111; // xori
                    3'b110: control_signal = 4'b0011; // ori
                    3'b001: control_signal = 4'b0100; // slli
                    3'b101: control_signal = (instruction[30] == 0) ? 4'b0101 : 4'b1010; // srli/srai
                    3'b010: control_signal = 4'b1100; // slti
                    3'b011: control_signal = 4'b0110; // sltiu
                    3'b111: control_signal = 4'b0010; // andi
                    default: control_signal = 4'b0000;
                endcase
            end
        end
        2'b11: case (instruction[14:12])
            3'b000: control_signal = (instruction[30] == 0) ? 4'b0000 : 4'b0001;
            3'b111: control_signal = 4'b0010;
            3'b110: control_signal = 4'b0011;
            3'b001: control_signal = 4'b0100;
            3'b101: control_signal = (instruction[30] == 0) ? 4'b0101 : 4'b1010;
            3'b010: control_signal = 4'b1100;
            3'b011: control_signal = 4'b0110;
            3'b100: control_signal = 4'b0111;
            default: control_signal = 4'b0000;
        endcase
        default: control_signal = 4'b0000;
    endcase
end
endmodule