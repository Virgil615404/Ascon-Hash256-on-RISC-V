`include "soc_addr_map.vh"

module axil_interconnect_1x3(
    input  logic        clk,
    input  logic        rst_n,

    // AXI-Lite slave port (from CPU-side master)
    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // AXI-Lite master port to RAM
    output logic [31:0] m_ram_awaddr,
    output logic        m_ram_awvalid,
    input  logic        m_ram_awready,

    output logic [31:0] m_ram_wdata,
    output logic [3:0]  m_ram_wstrb,
    output logic        m_ram_wvalid,
    input  logic        m_ram_wready,

    input  logic [1:0]  m_ram_bresp,
    input  logic        m_ram_bvalid,
    output logic        m_ram_bready,

    output logic [31:0] m_ram_araddr,
    output logic        m_ram_arvalid,
    input  logic        m_ram_arready,

    input  logic [31:0] m_ram_rdata,
    input  logic [1:0]  m_ram_rresp,
    input  logic        m_ram_rvalid,
    output logic        m_ram_rready,

    // AXI-Lite master port to UART
    output logic [31:0] m_uart_awaddr,
    output logic        m_uart_awvalid,
    input  logic        m_uart_awready,

    output logic [31:0] m_uart_wdata,
    output logic [3:0]  m_uart_wstrb,
    output logic        m_uart_wvalid,
    input  logic        m_uart_wready,

    input  logic [1:0]  m_uart_bresp,
    input  logic        m_uart_bvalid,
    output logic        m_uart_bready,

    output logic [31:0] m_uart_araddr,
    output logic        m_uart_arvalid,
    input  logic        m_uart_arready,

    input  logic [31:0] m_uart_rdata,
    input  logic [1:0]  m_uart_rresp,
    input  logic        m_uart_rvalid,
    output logic        m_uart_rready,

    // AXI-Lite master port to DMA control block
    output logic [31:0] m_dma_awaddr,
    output logic        m_dma_awvalid,
    input  logic        m_dma_awready,

    output logic [31:0] m_dma_wdata,
    output logic [3:0]  m_dma_wstrb,
    output logic        m_dma_wvalid,
    input  logic        m_dma_wready,

    input  logic [1:0]  m_dma_bresp,
    input  logic        m_dma_bvalid,
    output logic        m_dma_bready,

    output logic [31:0] m_dma_araddr,
    output logic        m_dma_arvalid,
    input  logic        m_dma_arready,

    input  logic [31:0] m_dma_rdata,
    input  logic [1:0]  m_dma_rresp,
    input  logic        m_dma_rvalid,
    output logic        m_dma_rready
);
    localparam logic [1:0] SEL_NONE = 2'd0;
    localparam logic [1:0] SEL_RAM  = 2'd1;
    localparam logic [1:0] SEL_UART = 2'd2;
    localparam logic [1:0] SEL_DMA  = 2'd3;

    logic [31:0] wr_awaddr_reg;
    logic [31:0] wr_wdata_reg;
    logic [3:0]  wr_wstrb_reg;
    logic        wr_aw_captured;
    logic        wr_w_captured;
    logic [1:0]  wr_sel;
    logic        wr_busy;
    logic        wr_aw_sent;
    logic        wr_w_sent;
    logic        wr_err_bvalid;

    logic [31:0] rd_araddr_reg;
    logic        rd_ar_captured;
    logic [1:0]  rd_sel;
    logic        rd_busy;
    logic        rd_ar_sent;
    logic        rd_err_rvalid;
    logic [31:0] rd_err_rdata;

    function automatic logic [1:0] decode_sel(input logic [31:0] addr);
        if (((addr >= `SOC_RAM_BASE) && (addr < (`SOC_RAM_BASE + `SOC_RAM_SIZE))) || (addr < `SOC_RAM_SIZE)) begin
            decode_sel = SEL_RAM;
        end else if ((addr >= `SOC_UART0_BASE) && (addr < (`SOC_UART0_BASE + `SOC_UART0_SIZE))) begin
            decode_sel = SEL_UART;
        end else if ((addr >= `SOC_DMA_ASCON_BASE) && (addr < (`SOC_DMA_ASCON_BASE + `SOC_DMA_ASCON_SIZE))) begin
            decode_sel = SEL_DMA;
        end else begin
            decode_sel = SEL_NONE;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_awaddr_reg  <= 32'd0;
            wr_wdata_reg   <= 32'd0;
            wr_wstrb_reg   <= 4'd0;
            wr_aw_captured <= 1'b0;
            wr_w_captured  <= 1'b0;
            wr_sel         <= SEL_NONE;
            wr_busy        <= 1'b0;
            wr_aw_sent     <= 1'b0;
            wr_w_sent      <= 1'b0;
            wr_err_bvalid  <= 1'b0;

            rd_araddr_reg  <= 32'd0;
            rd_ar_captured <= 1'b0;
            rd_sel         <= SEL_NONE;
            rd_busy        <= 1'b0;
            rd_ar_sent     <= 1'b0;
            rd_err_rvalid  <= 1'b0;
            rd_err_rdata   <= 32'hDEAD_BEEF;
        end else begin
            if (!wr_aw_captured && !wr_busy && s_axi_awvalid && s_axi_awready) begin
                wr_awaddr_reg  <= s_axi_awaddr;
                wr_aw_captured <= 1'b1;
            end

            if (!wr_w_captured && !wr_busy && s_axi_wvalid && s_axi_wready) begin
                wr_wdata_reg   <= s_axi_wdata;
                wr_wstrb_reg   <= s_axi_wstrb;
                wr_w_captured  <= 1'b1;
            end

            if (wr_aw_captured && wr_w_captured && !wr_busy) begin
                wr_sel        <= decode_sel(wr_awaddr_reg);
                wr_busy       <= 1'b1;
                wr_aw_sent    <= 1'b0;
                wr_w_sent     <= 1'b0;
                wr_err_bvalid <= (decode_sel(wr_awaddr_reg) == SEL_NONE);
            end

            if (wr_busy && (wr_sel == SEL_RAM || wr_sel == SEL_UART || wr_sel == SEL_DMA)) begin
                if (!wr_aw_sent) begin
                    if (wr_sel == SEL_RAM && m_ram_awready) wr_aw_sent <= 1'b1;
                    if (wr_sel == SEL_UART && m_uart_awready) wr_aw_sent <= 1'b1;
                    if (wr_sel == SEL_DMA && m_dma_awready) wr_aw_sent <= 1'b1;
                end

                if (!wr_w_sent) begin
                    if (wr_sel == SEL_RAM && m_ram_wready) wr_w_sent <= 1'b1;
                    if (wr_sel == SEL_UART && m_uart_wready) wr_w_sent <= 1'b1;
                    if (wr_sel == SEL_DMA && m_dma_wready) wr_w_sent <= 1'b1;
                end
            end

            if (wr_busy && wr_sel == SEL_NONE) begin
                if (wr_err_bvalid && s_axi_bready) begin
                    wr_busy        <= 1'b0;
                    wr_aw_captured <= 1'b0;
                    wr_w_captured  <= 1'b0;
                    wr_sel         <= SEL_NONE;
                    wr_err_bvalid  <= 1'b0;
                end
            end else if (wr_busy && wr_sel == SEL_RAM && wr_aw_sent && wr_w_sent && m_ram_bvalid && s_axi_bready) begin
                wr_busy        <= 1'b0;
                wr_aw_captured <= 1'b0;
                wr_w_captured  <= 1'b0;
                wr_sel         <= SEL_NONE;
                wr_aw_sent     <= 1'b0;
                wr_w_sent      <= 1'b0;
            end else if (wr_busy && wr_sel == SEL_UART && wr_aw_sent && wr_w_sent && m_uart_bvalid && s_axi_bready) begin
                wr_busy        <= 1'b0;
                wr_aw_captured <= 1'b0;
                wr_w_captured  <= 1'b0;
                wr_sel         <= SEL_NONE;
                wr_aw_sent     <= 1'b0;
                wr_w_sent      <= 1'b0;
            end else if (wr_busy && wr_sel == SEL_DMA && wr_aw_sent && wr_w_sent && m_dma_bvalid && s_axi_bready) begin
                wr_busy        <= 1'b0;
                wr_aw_captured <= 1'b0;
                wr_w_captured  <= 1'b0;
                wr_sel         <= SEL_NONE;
                wr_aw_sent     <= 1'b0;
                wr_w_sent      <= 1'b0;
            end

            if (!rd_ar_captured && !rd_busy && s_axi_arvalid && s_axi_arready) begin
                rd_araddr_reg  <= s_axi_araddr;
                rd_ar_captured <= 1'b1;
            end

            if (rd_ar_captured && !rd_busy) begin
                rd_sel        <= decode_sel(rd_araddr_reg);
                rd_busy       <= 1'b1;
                rd_ar_sent    <= 1'b0;
                rd_err_rvalid <= (decode_sel(rd_araddr_reg) == SEL_NONE);
                rd_err_rdata  <= 32'hDEAD_BEEF;
            end

            if (rd_busy && (rd_sel == SEL_RAM || rd_sel == SEL_UART || rd_sel == SEL_DMA) && !rd_ar_sent) begin
                if (rd_sel == SEL_RAM && m_ram_arready) rd_ar_sent <= 1'b1;
                if (rd_sel == SEL_UART && m_uart_arready) rd_ar_sent <= 1'b1;
                if (rd_sel == SEL_DMA && m_dma_arready) rd_ar_sent <= 1'b1;
            end

            if (rd_busy && rd_sel == SEL_NONE) begin
                if (rd_err_rvalid && s_axi_rready) begin
                    rd_busy        <= 1'b0;
                    rd_ar_captured <= 1'b0;
                    rd_sel         <= SEL_NONE;
                    rd_err_rvalid  <= 1'b0;
                end
            end else if (rd_busy && rd_sel == SEL_RAM && rd_ar_sent && m_ram_rvalid && s_axi_rready) begin
                rd_busy        <= 1'b0;
                rd_ar_captured <= 1'b0;
                rd_sel         <= SEL_NONE;
                rd_ar_sent     <= 1'b0;
            end else if (rd_busy && rd_sel == SEL_UART && rd_ar_sent && m_uart_rvalid && s_axi_rready) begin
                rd_busy        <= 1'b0;
                rd_ar_captured <= 1'b0;
                rd_sel         <= SEL_NONE;
                rd_ar_sent     <= 1'b0;
            end else if (rd_busy && rd_sel == SEL_DMA && rd_ar_sent && m_dma_rvalid && s_axi_rready) begin
                rd_busy        <= 1'b0;
                rd_ar_captured <= 1'b0;
                rd_sel         <= SEL_NONE;
                rd_ar_sent     <= 1'b0;
            end
        end
    end

    always_comb begin
        m_ram_awaddr  = wr_awaddr_reg;
        m_ram_awvalid = wr_busy && (wr_sel == SEL_RAM) && !wr_aw_sent;
        m_ram_wdata   = wr_wdata_reg;
        m_ram_wstrb   = wr_wstrb_reg;
        m_ram_wvalid  = wr_busy && (wr_sel == SEL_RAM) && !wr_w_sent;
        m_ram_bready  = wr_busy && (wr_sel == SEL_RAM) && wr_aw_sent && wr_w_sent && s_axi_bready;

        m_uart_awaddr  = wr_awaddr_reg;
        m_uart_awvalid = wr_busy && (wr_sel == SEL_UART) && !wr_aw_sent;
        m_uart_wdata   = wr_wdata_reg;
        m_uart_wstrb   = wr_wstrb_reg;
        m_uart_wvalid  = wr_busy && (wr_sel == SEL_UART) && !wr_w_sent;
        m_uart_bready  = wr_busy && (wr_sel == SEL_UART) && wr_aw_sent && wr_w_sent && s_axi_bready;

        m_dma_awaddr  = wr_awaddr_reg;
        m_dma_awvalid = wr_busy && (wr_sel == SEL_DMA) && !wr_aw_sent;
        m_dma_wdata   = wr_wdata_reg;
        m_dma_wstrb   = wr_wstrb_reg;
        m_dma_wvalid  = wr_busy && (wr_sel == SEL_DMA) && !wr_w_sent;
        m_dma_bready  = wr_busy && (wr_sel == SEL_DMA) && wr_aw_sent && wr_w_sent && s_axi_bready;

        m_ram_araddr  = rd_araddr_reg;
        m_ram_arvalid = rd_busy && (rd_sel == SEL_RAM) && !rd_ar_sent;
        m_ram_rready  = rd_busy && (rd_sel == SEL_RAM) && rd_ar_sent && s_axi_rready;

        m_uart_araddr  = rd_araddr_reg;
        m_uart_arvalid = rd_busy && (rd_sel == SEL_UART) && !rd_ar_sent;
        m_uart_rready  = rd_busy && (rd_sel == SEL_UART) && rd_ar_sent && s_axi_rready;

        m_dma_araddr  = rd_araddr_reg;
        m_dma_arvalid = rd_busy && (rd_sel == SEL_DMA) && !rd_ar_sent;
        m_dma_rready  = rd_busy && (rd_sel == SEL_DMA) && rd_ar_sent && s_axi_rready;

        s_axi_awready = !wr_aw_captured && !wr_busy;
        s_axi_wready  = !wr_w_captured && !wr_busy;

        if (wr_busy && wr_sel == SEL_RAM) begin
            s_axi_bresp  = m_ram_bresp;
            s_axi_bvalid = wr_aw_sent && wr_w_sent && m_ram_bvalid;
        end else if (wr_busy && wr_sel == SEL_UART) begin
            s_axi_bresp  = m_uart_bresp;
            s_axi_bvalid = wr_aw_sent && wr_w_sent && m_uart_bvalid;
        end else if (wr_busy && wr_sel == SEL_DMA) begin
            s_axi_bresp  = m_dma_bresp;
            s_axi_bvalid = wr_aw_sent && wr_w_sent && m_dma_bvalid;
        end else if (wr_busy && wr_sel == SEL_NONE) begin
            s_axi_bresp  = 2'b10;
            s_axi_bvalid = wr_err_bvalid;
        end else begin
            s_axi_bresp  = 2'b00;
            s_axi_bvalid = 1'b0;
        end

        s_axi_arready = !rd_ar_captured && !rd_busy;

        if (rd_busy && rd_sel == SEL_RAM) begin
            s_axi_rdata  = m_ram_rdata;
            s_axi_rresp  = m_ram_rresp;
            s_axi_rvalid = rd_ar_sent && m_ram_rvalid;
        end else if (rd_busy && rd_sel == SEL_UART) begin
            s_axi_rdata  = m_uart_rdata;
            s_axi_rresp  = m_uart_rresp;
            s_axi_rvalid = rd_ar_sent && m_uart_rvalid;
        end else if (rd_busy && rd_sel == SEL_DMA) begin
            s_axi_rdata  = m_dma_rdata;
            s_axi_rresp  = m_dma_rresp;
            s_axi_rvalid = rd_ar_sent && m_dma_rvalid;
        end else if (rd_busy && rd_sel == SEL_NONE) begin
            s_axi_rdata  = rd_err_rdata;
            s_axi_rresp  = 2'b10;
            s_axi_rvalid = rd_err_rvalid;
        end else begin
            s_axi_rdata  = 32'd0;
            s_axi_rresp  = 2'b00;
            s_axi_rvalid = 1'b0;
        end
    end
endmodule