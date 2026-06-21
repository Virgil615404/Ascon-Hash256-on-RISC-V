`include "soc_addr_map.vh"

module axil_ram_slave(
    input  logic        clk,
    input  logic        rst_n,

    // AXI-Lite slave write address
    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // AXI-Lite slave write data
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // AXI-Lite slave write response
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // AXI-Lite slave read address
    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // AXI-Lite slave read data
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready
);
    logic [31:0] ram_addr;
    logic [31:0] ram_rdata;
    logic        ram_we;

    logic [31:0] awaddr_reg;
    logic [31:0] wdata_reg;
    logic [3:0]  wstrb_reg;
    logic        aw_captured;
    logic        w_captured;
    logic        bvalid_reg;

    logic [31:0] araddr_reg;
    logic        read_pending;
    logic        read_wait;
    logic [31:0] rdata_reg;
    logic        rvalid_reg;

    logic [31:0] write_addr_off;
    logic [31:0] read_addr_off;

    assign write_addr_off = awaddr_reg - (awaddr_reg >= `SOC_RAM_BASE ? `SOC_RAM_BASE : 32'h0000_0000);
    assign read_addr_off  = araddr_reg - (araddr_reg >= `SOC_RAM_BASE ? `SOC_RAM_BASE : 32'h0000_0000);

    assign ram_addr = (aw_captured && w_captured && !bvalid_reg) ? write_addr_off : read_addr_off;

    assign ram_we = aw_captured && w_captured && !bvalid_reg;

    assign s_axi_awready = !aw_captured;
    assign s_axi_wready  = !w_captured;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = bvalid_reg;

    assign s_axi_arready = !read_pending && !rvalid_reg;
    assign s_axi_rdata   = rdata_reg;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rvalid  = rvalid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awaddr_reg    <= 32'd0;
            wdata_reg     <= 32'd0;
            wstrb_reg     <= 4'd0;
            aw_captured   <= 1'b0;
            w_captured    <= 1'b0;
            bvalid_reg    <= 1'b0;
            araddr_reg    <= 32'd0;
            read_pending  <= 1'b0;
            read_wait     <= 1'b0;
            rdata_reg     <= 32'd0;
            rvalid_reg    <= 1'b0;
        end else begin
            if (!aw_captured && s_axi_awvalid && s_axi_awready) begin
                awaddr_reg  <= s_axi_awaddr;
                aw_captured <= 1'b1;
            end

            if (!w_captured && s_axi_wvalid && s_axi_wready) begin
                wdata_reg   <= s_axi_wdata;
                wstrb_reg   <= s_axi_wstrb;
                w_captured  <= 1'b1;
            end

            if (aw_captured && w_captured && !bvalid_reg) begin
                bvalid_reg  <= 1'b1;
                aw_captured <= 1'b0;
                w_captured  <= 1'b0;
            end else if (bvalid_reg && s_axi_bready) begin
                bvalid_reg  <= 1'b0;
            end

            if (!read_pending && !rvalid_reg && s_axi_arvalid && s_axi_arready) begin
                araddr_reg   <= s_axi_araddr;
                read_pending <= 1'b1;
            end

            if (read_pending) begin
                read_wait    <= 1'b1;
                read_pending <= 1'b0;
            end else if (read_wait) begin
                rdata_reg    <= ram_rdata;
                rvalid_reg   <= 1'b1;
                read_wait    <= 1'b0;
            end else if (rvalid_reg && s_axi_rready) begin
                rvalid_reg   <= 1'b0;
            end
        end
    end

    soc_ram u_ram (
        .clk  (clk),
        .rst_n(rst_n),
        .we   (ram_we),
        .wstrb(wstrb_reg),
        .addr (ram_addr),
        .wdata(wdata_reg),
        .rdata(ram_rdata)
    );
endmodule
