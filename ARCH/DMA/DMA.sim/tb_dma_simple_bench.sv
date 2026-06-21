`timescale 1ns/1ps
`include "../DMA.srcs/soc_addr_map.vh"

module tb_dma_simple_bench;
    localparam int MAX_WORDS = 2048;
    localparam int TB_PAYLOAD_BYTES = 4;
    localparam int TB_MAX_CYCLES = 2000000;

    logic clk;
    logic rst_n;

    logic [31:0] dma_awaddr;
    logic        dma_awvalid;
    logic        dma_awready;
    logic [31:0] dma_wdata;
    logic [3:0]  dma_wstrb;
    logic        dma_wvalid;
    logic        dma_wready;
    logic [1:0]  dma_bresp;
    logic        dma_bvalid;
    logic        dma_bready;
    logic [31:0] dma_araddr;
    logic        dma_arvalid;
    logic        dma_arready;
    logic [31:0] dma_rdata;
    logic [1:0]  dma_rresp;
    logic        dma_rvalid;
    logic        dma_rready;

    logic [31:0] ram_awaddr;
    logic        ram_awvalid;
    logic        ram_awready;
    logic [31:0] ram_wdata;
    logic [3:0]  ram_wstrb;
    logic        ram_wvalid;
    logic        ram_wready;
    logic [1:0]  ram_bresp;
    logic        ram_bvalid;
    logic        ram_bready;
    logic [31:0] ram_araddr;
    logic        ram_arvalid;
    logic        ram_arready;
    logic [31:0] ram_rdata;
    logic [1:0]  ram_rresp;
    logic        ram_rvalid;
    logic        ram_rready;

    logic [31:0] dma_ram_addr;
    logic [31:0] dma_ram_rdata;

    int unsigned cycle_count;
    int unsigned first_accept_cycle;
    int unsigned issue_cycle;
    int unsigned busy_start_cycle;
    int unsigned done_cycle;
    int unsigned word_count;
    int unsigned next_cycle;

    bit first_accept_seen;
    bit prev_busy;
    bit prev_done;
    bit busy_seen;
    bit done_seen;

    logic [31:0] message_words [0:MAX_WORDS-1];
    logic [31:0] status_value;
    logic [31:0] digest0_value;

    always #5 clk = ~clk;

    axil_dma_asconhash256 dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axi_awaddr (dma_awaddr),
        .s_axi_awvalid(dma_awvalid),
        .s_axi_awready(dma_awready),
        .s_axi_wdata  (dma_wdata),
        .s_axi_wstrb  (dma_wstrb),
        .s_axi_wvalid (dma_wvalid),
        .s_axi_wready (dma_wready),
        .s_axi_bresp  (dma_bresp),
        .s_axi_bvalid (dma_bvalid),
        .s_axi_bready (dma_bready),
        .s_axi_araddr (dma_araddr),
        .s_axi_arvalid(dma_arvalid),
        .s_axi_arready(dma_arready),
        .s_axi_rdata  (dma_rdata),
        .s_axi_rresp  (dma_rresp),
        .s_axi_rvalid (dma_rvalid),
        .s_axi_rready (dma_rready),
        .ram_dma_addr (dma_ram_addr),
        .ram_dma_rdata(dma_ram_rdata)
    );

    axil_ram_slave u_ram (
        .clk          (clk),
        .rst_n        (rst_n),
        .dma_addr     (dma_ram_addr),
        .dma_rdata    (dma_ram_rdata),
        .s_axi_awaddr (ram_awaddr),
        .s_axi_awvalid(ram_awvalid),
        .s_axi_awready(ram_awready),
        .s_axi_wdata  (ram_wdata),
        .s_axi_wstrb  (ram_wstrb),
        .s_axi_wvalid (ram_wvalid),
        .s_axi_wready (ram_wready),
        .s_axi_bresp  (ram_bresp),
        .s_axi_bvalid (ram_bvalid),
        .s_axi_bready (ram_bready),
        .s_axi_araddr (ram_araddr),
        .s_axi_arvalid(ram_arvalid),
        .s_axi_arready(ram_arready),
        .s_axi_rdata  (ram_rdata),
        .s_axi_rresp  (ram_rresp),
        .s_axi_rvalid (ram_rvalid),
        .s_axi_rready (ram_rready)
    );

    task automatic axi_write_dma(input logic [31:0] addr, input logic [31:0] data);
        int unsigned guard_cycles;
        begin
            dma_awaddr  = addr;
            dma_awvalid = 1'b1;
            dma_wdata   = data;
            dma_wstrb   = 4'hF;
            dma_wvalid  = 1'b1;
            dma_bready  = 1'b0;

            @(posedge clk);
            guard_cycles = 0;
            while (!dma_bvalid) begin
                if (guard_cycles > 100) begin
                    $fatal(1, "DMA AXI-Lite write timeout addr=0x%08h data=0x%08h", addr, data);
                end
                guard_cycles++;
                @(posedge clk);
            end

            dma_awvalid = 1'b0;
            dma_wvalid  = 1'b0;
            dma_bready  = 1'b1;
            @(posedge clk);
            dma_bready  = 1'b0;
        end
    endtask

    task automatic axi_read_dma(input logic [31:0] addr, output logic [31:0] data);
        int unsigned guard_cycles;
        begin
            dma_araddr  = addr;
            dma_arvalid = 1'b1;
            dma_rready  = 1'b0;

            @(posedge clk);
            dma_arvalid = 1'b0;
            guard_cycles = 0;

            while (!dma_rvalid) begin
                if (guard_cycles > 100) begin
                    $fatal(1, "DMA AXI-Lite read timeout addr=0x%08h", addr);
                end
                guard_cycles++;
                @(posedge clk);
            end

            data = dma_rdata;
            dma_rready = 1'b1;
            @(posedge clk);
            dma_rready = 1'b0;
        end
    endtask

    task automatic axi_write_ram(input logic [31:0] addr, input logic [31:0] data);
        int unsigned guard_cycles;
        begin
            ram_awaddr  = addr;
            ram_awvalid = 1'b1;
            ram_wdata   = data;
            ram_wstrb   = 4'hF;
            ram_wvalid  = 1'b1;
            ram_bready  = 1'b0;

            @(posedge clk);
            guard_cycles = 0;
            while (!ram_bvalid) begin
                if (guard_cycles > 100) begin
                    $fatal(1, "RAM AXI-Lite write timeout addr=0x%08h data=0x%08h", addr, data);
                end
                guard_cycles++;
                @(posedge clk);
            end

            ram_awvalid = 1'b0;
            ram_wvalid  = 1'b0;
            ram_bready  = 1'b1;
            @(posedge clk);
            ram_bready  = 1'b0;
        end
    endtask

    task automatic fill_message_words(input int unsigned bytes);
        int unsigned i;
        begin
            for (i = 0; i < MAX_WORDS; i++) begin
                message_words[i] = {8'(i * 4), 8'(i * 4 + 1), 8'(i * 4 + 2), 8'(i * 4 + 3)};
            end
            if ((bytes == 0) || ((bytes % 4) != 0)) begin
                $fatal(1, "TB_PAYLOAD_BYTES must be a non-zero multiple of 4, got %0d", bytes);
            end
            word_count = bytes / 4;
            if (word_count > MAX_WORDS) begin
                $fatal(1, "TB_PAYLOAD_BYTES too large for this bench: %0d bytes", bytes);
            end
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
            first_accept_cycle <= 0;
            prev_busy <= 1'b0;
            prev_done <= 1'b0;
            first_accept_seen <= 1'b0;
            busy_seen <= 1'b0;
            done_seen <= 1'b0;
            busy_start_cycle <= 0;
            done_cycle <= 0;
        end else begin
            next_cycle = cycle_count + 1;
            cycle_count <= next_cycle;

            if (!first_accept_seen && dut.bdi_ready && (|dut.bdi_valid_mask)) begin
                first_accept_seen <= 1'b1;
                first_accept_cycle <= next_cycle;
                $display("[TB][DMA-SIMPLE] first_accept_cycle=%0d", next_cycle);
            end

            if (dut.busy_reg && !prev_busy && !busy_seen) begin
                busy_seen <= 1'b1;
                busy_start_cycle <= next_cycle;
                $display("[TB][DMA-SIMPLE] BUSY asserted at cycle=%0d", next_cycle);
            end

            if (dut.done_reg && !prev_done && !done_seen) begin
                done_seen <= 1'b1;
                done_cycle <= next_cycle;
                $display("[TB][DMA-SIMPLE] DONE asserted at cycle=%0d", next_cycle);
            end

            prev_busy <= dut.busy_reg;
            prev_done <= dut.done_reg;
        end
    end

    initial begin
        int unsigned issue_to_done_cycles;
        int unsigned unified_cycles;
        real bytes_per_cycle_unified;
        real throughput_mb_s_unified;
        real bytes_per_cycle_e2e;
        real throughput_mb_s_e2e;

        clk = 1'b0;
        rst_n = 1'b0;

        dma_awaddr = 32'd0;
        dma_awvalid = 1'b0;
        dma_wdata = 32'd0;
        dma_wstrb = 4'd0;
        dma_wvalid = 1'b0;
        dma_bready = 1'b0;
        dma_araddr = 32'd0;
        dma_arvalid = 1'b0;
        dma_rready = 1'b0;

        ram_awaddr = 32'd0;
        ram_awvalid = 1'b0;
        ram_wdata = 32'd0;
        ram_wstrb = 4'd0;
        ram_wvalid = 1'b0;
        ram_bready = 1'b0;
        ram_araddr = 32'd0;
        ram_arvalid = 1'b0;
        ram_rready = 1'b0;

        $display("[TB][CFG] TB_PAYLOAD_BYTES=%0d", TB_PAYLOAD_BYTES);
        $display("[TB][CFG] TB_MAX_CYCLES=%0d", TB_MAX_CYCLES);

        fill_message_words(TB_PAYLOAD_BYTES);

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("[TB][DMA-SIMPLE] Starting standalone DMA benchmark");
        $display("[TB][DMA-SIMPLE] payload=%0d bytes words=%0d base_ram=0x%08h base_dma=0x%08h", TB_PAYLOAD_BYTES, word_count, `SOC_RAM_BASE, `SOC_DMA_ASCON_BASE);

        for (int unsigned i = 0; i < word_count; i++) begin
            axi_write_ram(`SOC_RAM_BASE + (i * 4), message_words[i]);
        end

        axi_write_dma(`SOC_DMA_ASCON_BASE + 32'h04, `SOC_RAM_BASE);
        axi_write_dma(`SOC_DMA_ASCON_BASE + 32'h08, TB_PAYLOAD_BYTES[31:0]);

        issue_cycle = cycle_count;
        axi_write_dma(`SOC_DMA_ASCON_BASE + 32'h00, 32'h0000_0001);

        while (!done_seen && (cycle_count < TB_MAX_CYCLES)) begin
            @(posedge clk);
        end

        if (!done_seen) begin
            $fatal(1, "DMA did not finish within %0d cycles", TB_MAX_CYCLES);
        end

        issue_to_done_cycles = done_cycle - issue_cycle;
        unified_cycles = done_cycle - first_accept_cycle;
        if (unified_cycles == 0) begin
            $fatal(1, "Invalid unified cycle count: 0");
        end
        if (issue_to_done_cycles == 0) begin
            $fatal(1, "Invalid end-to-end cycle count: 0");
        end

        axi_read_dma(`SOC_DMA_ASCON_BASE + 32'h0C, status_value);
        axi_read_dma(`SOC_DMA_ASCON_BASE + 32'h10, digest0_value);

        bytes_per_cycle_unified = real'(TB_PAYLOAD_BYTES) / real'(unified_cycles);
        throughput_mb_s_unified = bytes_per_cycle_unified * 100.0;
        bytes_per_cycle_e2e = real'(TB_PAYLOAD_BYTES) / real'(issue_to_done_cycles);
        throughput_mb_s_e2e = bytes_per_cycle_e2e * 100.0;

        $display("[TB][DMA-SIMPLE] issue_cycle=%0d first_accept_cycle=%0d busy_start_cycle=%0d done_cycle=%0d", issue_cycle, first_accept_cycle, busy_start_cycle, done_cycle);
        $display("[TB][DMA-SIMPLE] issue_to_done_cycles=%0d unified_cycles=%0d", issue_to_done_cycles, unified_cycles);
        $display("[TB][DMA-SIMPLE][PERF_UNIFIED] bytes=%0d bytes_per_cycle=%0.2f throughput=%0.2f MB/s @100MHz", TB_PAYLOAD_BYTES, bytes_per_cycle_unified, throughput_mb_s_unified);
        $display("[TB][DMA-SIMPLE][PERF_E2E] bytes=%0d bytes_per_cycle=%0.2f throughput=%0.2f MB/s @100MHz", TB_PAYLOAD_BYTES, bytes_per_cycle_e2e, throughput_mb_s_e2e);
        $display("[TB][DMA-SIMPLE] STATUS=0x%08h DIGEST0=0x%08h", status_value, digest0_value);
        $display("[TB][DMA-SIMPLE] PASS");

        $finish;
    end
endmodule









