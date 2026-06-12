module instruction_mem_hex #(
    parameter HEX_FILE = "program.hex",
    parameter MEM_WORDS = 256
)(
    input         valid,
    input  [9:0]  addr,
    output        ready,
    output [31:0] rdata
);
    reg [31:0] mem [0:MEM_WORDS-1];
    integer i;
    reg [1023:0] hex_path;

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            mem[i] = 32'h00000013;
        end
        hex_path = HEX_FILE;
        if ($value$plusargs("HEX=%s", hex_path)) begin
            $display("[instruction_mem_hex] override HEX=%0s", hex_path);
        end
        if (hex_path != "") begin
            $readmemh(hex_path, mem);
            if ($test$plusargs("IMEM_TRACE")) begin
                $display("[instruction_mem_hex] loaded HEX=%0s mem0=%08h mem1=%08h mem2=%08h mem3=%08h", hex_path, mem[0], mem[1], mem[2], mem[3]);
            end
        end
    end

    assign ready = valid;
    assign rdata = mem[addr[9:2]];
endmodule
