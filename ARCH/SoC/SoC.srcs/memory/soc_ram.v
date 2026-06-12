module soc_ram #(
    parameter RAM_WORDS = 16384  // 64KB / 4
)(
    input         clk,
    input         rst_n,
    input         we,
    input  [3:0]  wstrb,
    input  [31:0] addr,
    input  [31:0] wdata,
    output reg [31:0] rdata
);
    (* ram_style = "block" *) reg [31:0] mem [0:RAM_WORDS-1];

    wire [31:0] word_addr = addr[31:2];
    wire [13:0] idx = word_addr[13:0];

    always @(posedge clk) begin
        if (we) begin
            if (wstrb[0]) mem[idx][7:0]   <= wdata[7:0];
            if (wstrb[1]) mem[idx][15:8]  <= wdata[15:8];
            if (wstrb[2]) mem[idx][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[idx][31:24] <= wdata[31:24];
        end

        rdata <= mem[idx];
    end
endmodule
