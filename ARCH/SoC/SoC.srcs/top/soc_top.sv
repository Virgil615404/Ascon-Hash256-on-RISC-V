module soc_top #(
    parameter IMEM_HEX_FILE = "../programs/coverage_all.hex"
)(
    input  logic clk,
    input  logic rst_n,
    input  logic uart_rx_i,
    output logic uart_tx_o,

    output logic [31:0] dbg_instr,
    output logic [9:0]  dbg_pc,
    output logic [31:0] dbg_alu,
    output logic [4:0]  dbg_rd
);
    logic        dmem_valid;
    logic        dmem_we;
    logic [2:0]  dmem_size;
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic        dmem_ready;
    logic [31:0] dmem_rdata;

    logic        imem_valid;
    logic [9:0]  imem_addr;
    logic        imem_ready;
    logic [31:0] imem_rdata;

    logic        ic_mem_valid;
    logic [9:0]  ic_mem_addr;
    logic        ic_mem_ready;
    logic [31:0] ic_mem_rdata;

    logic        dcache_mem_valid;
    logic        dcache_mem_we;
    logic [31:0] dcache_mem_addr;
    logic [31:0] dcache_mem_wdata;
    logic        dcache_mem_ready;
    logic [31:0] dcache_mem_rdata;

    // AXI-Lite link between CPU bridge and interconnect
    logic [31:0] m_axi_awaddr;
    logic        m_axi_awvalid;
    logic        m_axi_awready;
    logic [31:0] m_axi_wdata;
    logic [3:0]  m_axi_wstrb;
    logic        m_axi_wvalid;
    logic        m_axi_wready;
    logic [1:0]  m_axi_bresp;
    logic        m_axi_bvalid;
    logic        m_axi_bready;
    logic [31:0] m_axi_araddr;
    logic        m_axi_arvalid;
    logic        m_axi_arready;
    logic [31:0] m_axi_rdata;
    logic [1:0]  m_axi_rresp;
    logic        m_axi_rvalid;
    logic        m_axi_rready;

    // AXI-Lite link from interconnect to RAM slave
    logic [31:0] ram_axi_awaddr;
    logic        ram_axi_awvalid;
    logic        ram_axi_awready;
    logic [31:0] ram_axi_wdata;
    logic [3:0]  ram_axi_wstrb;
    logic        ram_axi_wvalid;
    logic        ram_axi_wready;
    logic [1:0]  ram_axi_bresp;
    logic        ram_axi_bvalid;
    logic        ram_axi_bready;
    logic [31:0] ram_axi_araddr;
    logic        ram_axi_arvalid;
    logic        ram_axi_arready;
    logic [31:0] ram_axi_rdata;
    logic [1:0]  ram_axi_rresp;
    logic        ram_axi_rvalid;
    logic        ram_axi_rready;

    // AXI-Lite link from interconnect to UART slave
    logic [31:0] uart_axi_awaddr;
    logic        uart_axi_awvalid;
    logic        uart_axi_awready;
    logic [31:0] uart_axi_wdata;
    logic [3:0]  uart_axi_wstrb;
    logic        uart_axi_wvalid;
    logic        uart_axi_wready;
    logic [1:0]  uart_axi_bresp;
    logic        uart_axi_bvalid;
    logic        uart_axi_bready;
    logic [31:0] uart_axi_araddr;
    logic        uart_axi_arvalid;
    logic        uart_axi_arready;
    logic [31:0] uart_axi_rdata;
    logic [1:0]  uart_axi_rresp;
    logic        uart_axi_rvalid;
    logic        uart_axi_rready;

    cpu_core_soc u_cpu (
        .clk       (clk),
        .rst_n     (rst_n),
        .imem_valid(imem_valid),
        .imem_addr (imem_addr),
        .imem_ready(imem_ready),
        .imem_rdata(imem_rdata),
        .dmem_valid(dmem_valid),
        .dmem_we   (dmem_we),
        .dmem_size (dmem_size),
        .dmem_addr (dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_ready(dmem_ready),
        .dmem_rdata(dmem_rdata),
        .instruct  (dbg_instr),
        .address   (dbg_pc),
        .ALU_result(dbg_alu),
        .rd_address(dbg_rd)
    );

    l1_icache u_icache (
        .clk      (clk),
        .rst_n    (rst_n),
        .cpu_valid(imem_valid),
        .cpu_addr (imem_addr),
        .cpu_ready(imem_ready),
        .cpu_rdata(imem_rdata),
        .mem_valid(ic_mem_valid),
        .mem_addr (ic_mem_addr),
        .mem_ready(ic_mem_ready),
        .mem_rdata(ic_mem_rdata)
    );

    instruction_mem_hex #(
        .HEX_FILE(IMEM_HEX_FILE)
    ) u_imem (
        .valid(ic_mem_valid),
        .addr (ic_mem_addr),
        .ready(ic_mem_ready),
        .rdata(ic_mem_rdata)
    );

    l1_dcache u_dcache (
        .clk      (clk),
        .rst_n    (rst_n),
        .cpu_valid(dmem_valid),
        .cpu_we   (dmem_we),
        .cpu_size (dmem_size),
        .cpu_addr (dmem_addr),
        .cpu_wdata(dmem_wdata),
        .cpu_ready(dmem_ready),
        .cpu_rdata(dmem_rdata),
        .mem_valid(dcache_mem_valid),
        .mem_we   (dcache_mem_we),
        .mem_addr (dcache_mem_addr),
        .mem_wdata(dcache_mem_wdata),
        .mem_ready(dcache_mem_ready),
        .mem_rdata(dcache_mem_rdata)
    );

    cpu_native_to_axil u_cpu2axil (
        .clk          (clk),
        .rst_n        (rst_n),
        .dmem_valid   (dcache_mem_valid),
        .dmem_we      (dcache_mem_we),
        .dmem_addr    (dcache_mem_addr),
        .dmem_wdata   (dcache_mem_wdata),
        .dmem_ready   (dcache_mem_ready),
        .dmem_rdata   (dcache_mem_rdata),
        .m_axi_awaddr (m_axi_awaddr),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata  (m_axi_wdata),
        .m_axi_wstrb  (m_axi_wstrb),
        .m_axi_wvalid (m_axi_wvalid),
        .m_axi_wready (m_axi_wready),
        .m_axi_bresp  (m_axi_bresp),
        .m_axi_bvalid (m_axi_bvalid),
        .m_axi_bready (m_axi_bready),
        .m_axi_araddr (m_axi_araddr),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata  (m_axi_rdata),
        .m_axi_rresp  (m_axi_rresp),
        .m_axi_rvalid (m_axi_rvalid),
        .m_axi_rready (m_axi_rready)
    );

    axil_interconnect_1x2 u_axil_ic (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axi_awaddr (m_axi_awaddr),
        .s_axi_awvalid(m_axi_awvalid),
        .s_axi_awready(m_axi_awready),
        .s_axi_wdata  (m_axi_wdata),
        .s_axi_wstrb  (m_axi_wstrb),
        .s_axi_wvalid (m_axi_wvalid),
        .s_axi_wready (m_axi_wready),
        .s_axi_bresp  (m_axi_bresp),
        .s_axi_bvalid (m_axi_bvalid),
        .s_axi_bready (m_axi_bready),
        .s_axi_araddr (m_axi_araddr),
        .s_axi_arvalid(m_axi_arvalid),
        .s_axi_arready(m_axi_arready),
        .s_axi_rdata  (m_axi_rdata),
        .s_axi_rresp  (m_axi_rresp),
        .s_axi_rvalid (m_axi_rvalid),
        .s_axi_rready (m_axi_rready),
        .m_ram_awaddr (ram_axi_awaddr),
        .m_ram_awvalid(ram_axi_awvalid),
        .m_ram_awready(ram_axi_awready),
        .m_ram_wdata  (ram_axi_wdata),
        .m_ram_wstrb  (ram_axi_wstrb),
        .m_ram_wvalid (ram_axi_wvalid),
        .m_ram_wready (ram_axi_wready),
        .m_ram_bresp  (ram_axi_bresp),
        .m_ram_bvalid (ram_axi_bvalid),
        .m_ram_bready (ram_axi_bready),
        .m_ram_araddr (ram_axi_araddr),
        .m_ram_arvalid(ram_axi_arvalid),
        .m_ram_arready(ram_axi_arready),
        .m_ram_rdata  (ram_axi_rdata),
        .m_ram_rresp  (ram_axi_rresp),
        .m_ram_rvalid (ram_axi_rvalid),
        .m_ram_rready (ram_axi_rready),
        .m_uart_awaddr (uart_axi_awaddr),
        .m_uart_awvalid(uart_axi_awvalid),
        .m_uart_awready(uart_axi_awready),
        .m_uart_wdata  (uart_axi_wdata),
        .m_uart_wstrb  (uart_axi_wstrb),
        .m_uart_wvalid (uart_axi_wvalid),
        .m_uart_wready (uart_axi_wready),
        .m_uart_bresp  (uart_axi_bresp),
        .m_uart_bvalid (uart_axi_bvalid),
        .m_uart_bready (uart_axi_bready),
        .m_uart_araddr (uart_axi_araddr),
        .m_uart_arvalid(uart_axi_arvalid),
        .m_uart_arready(uart_axi_arready),
        .m_uart_rdata  (uart_axi_rdata),
        .m_uart_rresp  (uart_axi_rresp),
        .m_uart_rvalid (uart_axi_rvalid),
        .m_uart_rready (uart_axi_rready)
    );

    axil_ram_slave u_ram_axi (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axi_awaddr (ram_axi_awaddr),
        .s_axi_awvalid(ram_axi_awvalid),
        .s_axi_awready(ram_axi_awready),
        .s_axi_wdata  (ram_axi_wdata),
        .s_axi_wstrb  (ram_axi_wstrb),
        .s_axi_wvalid (ram_axi_wvalid),
        .s_axi_wready (ram_axi_wready),
        .s_axi_bresp  (ram_axi_bresp),
        .s_axi_bvalid (ram_axi_bvalid),
        .s_axi_bready (ram_axi_bready),
        .s_axi_araddr (ram_axi_araddr),
        .s_axi_arvalid(ram_axi_arvalid),
        .s_axi_arready(ram_axi_arready),
        .s_axi_rdata  (ram_axi_rdata),
        .s_axi_rresp  (ram_axi_rresp),
        .s_axi_rvalid (ram_axi_rvalid),
        .s_axi_rready (ram_axi_rready)
    );

    axil_uart_slave #(
        .CLK_FREQ (100_000_000),
        .BAUD_RATE(9600)
    ) u_uart_axi (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axi_awaddr (uart_axi_awaddr),
        .s_axi_awvalid(uart_axi_awvalid),
        .s_axi_awready(uart_axi_awready),
        .s_axi_wdata  (uart_axi_wdata),
        .s_axi_wstrb  (uart_axi_wstrb),
        .s_axi_wvalid (uart_axi_wvalid),
        .s_axi_wready (uart_axi_wready),
        .s_axi_bresp  (uart_axi_bresp),
        .s_axi_bvalid (uart_axi_bvalid),
        .s_axi_bready (uart_axi_bready),
        .s_axi_araddr (uart_axi_araddr),
        .s_axi_arvalid(uart_axi_arvalid),
        .s_axi_arready(uart_axi_arready),
        .s_axi_rdata  (uart_axi_rdata),
        .s_axi_rresp  (uart_axi_rresp),
        .s_axi_rvalid (uart_axi_rvalid),
        .s_axi_rready (uart_axi_rready),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o)
    );
endmodule
