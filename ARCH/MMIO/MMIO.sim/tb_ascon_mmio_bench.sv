`timescale 1ns/1ps
`include "../MMIO.srcs/soc_addr_map.vh"

module tb_ascon_mmio_bench;
    localparam int MAX_WORDS = 2048;
    localparam int TB_PAYLOAD_BYTES = 4;
    localparam int TB_MAX_CYCLES = 20000;

    logic clk;
    logic rst_n;

    int unsigned cycle_count;
    int unsigned first_accept_cycle;
    int unsigned done_cycle;
    bit first_accept_seen;
    bit done_seen;
    logic [31:0] message_words [0:MAX_WORDS-1];

    logic [31:0] s_awaddr;
    logic        s_awvalid;
    logic        s_awready;
    logic [31:0] s_wdata;
    logic [3:0]  s_wstrb;
    logic        s_wvalid;
    logic        s_wready;
    logic [1:0]  s_bresp;
    logic        s_bvalid;
    logic        s_bready;
    logic [31:0] s_araddr;
    logic        s_arvalid;
    logic        s_arready;
    logic [31:0] s_rdata;
    logic [1:0]  s_rresp;
    logic        s_rvalid;
    logic        s_rready;

    axil_ascon_slave #(.IN_WORDS(2048), .OUT_WORDS(2048)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_awaddr), .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
        .s_axi_wdata(s_wdata), .s_axi_wstrb(s_wstrb), .s_axi_wvalid(s_wvalid), .s_axi_wready(s_wready),
        .s_axi_bresp(s_bresp), .s_axi_bvalid(s_bvalid), .s_axi_bready(s_bready),
        .s_axi_araddr(s_araddr), .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
        .s_axi_rdata(s_rdata), .s_axi_rresp(s_rresp), .s_axi_rvalid(s_rvalid), .s_axi_rready(s_rready)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic axi_write(input logic [31:0] addr, input logic [31:0] data);
        int unsigned guard_cycles;
        begin
            s_awaddr  = addr;
            s_awvalid = 1'b1;
            s_wdata   = data;
            s_wstrb   = 4'hF;
            s_wvalid  = 1'b1;
            s_bready  = 1'b0;

            @(posedge clk);
            guard_cycles = 0;
            while (!s_bvalid) begin
                if (guard_cycles > 100) begin
                    $fatal(1, "AXI write timeout addr=0x%08h data=0x%08h", addr, data);
                end
                guard_cycles++;
                @(posedge clk);
            end

            s_awvalid = 1'b0;
            s_wvalid  = 1'b0;
            s_bready  = 1'b1;
            @(posedge clk);
            s_bready  = 1'b0;
        end
    endtask

    task automatic axi_read(input logic [31:0] addr, output logic [31:0] data);
        int unsigned guard_cycles;
        begin
            s_araddr  = addr;
            s_arvalid = 1'b1;
            s_rready  = 1'b0;

            @(posedge clk);
            s_arvalid = 1'b0;

            guard_cycles = 0;
            while (!s_rvalid) begin
                if (guard_cycles > 100) begin
                    $fatal(1, "AXI read timeout addr=0x%08h", addr);
                end
                guard_cycles++;
                @(posedge clk);
            end

            data = s_rdata;
            s_rready = 1'b1;
            @(posedge clk);
            s_rready = 1'b0;
        end
    endtask

    task automatic wait_for_done(output logic [31:0] status, input int unsigned max_cycles, output int unsigned elapsed_cycles);
        elapsed_cycles = 0;
        status = 32'd0;
        while (elapsed_cycles < max_cycles) begin
            axi_read(`SOC_ASCON_BASE + 32'h04, status);
            if (status == 32'd2) begin
                return;
            end
            elapsed_cycles++;
        end
        $fatal(1, "ASCON did not reach DONE within %0d poll cycles", max_cycles);
    endtask

    task automatic fill_message_words(input int unsigned bytes, output int unsigned word_count);
        int unsigned i;
        begin
            if ((bytes == 0) || ((bytes % 4) != 0)) begin
                $fatal(1, "TB_PAYLOAD_BYTES must be a non-zero multiple of 4, got %0d", bytes);
            end

            word_count = bytes / 4;
            if (word_count > MAX_WORDS) begin
                $fatal(1, "TB_PAYLOAD_BYTES too large for this bench: %0d bytes", bytes);
            end

            for (i = 0; i < word_count; i++) begin
                message_words[i] = {8'(i * 4), 8'(i * 4 + 1), 8'(i * 4 + 2), 8'(i * 4 + 3)};
            end
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        int unsigned next_cycle;

        if (!rst_n) begin
            cycle_count <= 0;
            first_accept_cycle <= 0;
            done_cycle <= 0;
            first_accept_seen <= 1'b0;
            done_seen <= 1'b0;
        end else begin
            next_cycle = cycle_count + 1;
            cycle_count <= next_cycle;

            if (!first_accept_seen && dut.u_ascon_core.bdi_ready && (|dut.bdi_valid)) begin
                first_accept_seen <= 1'b1;
                first_accept_cycle <= next_cycle;
            end

            if (!done_seen && dut.done_int) begin
                done_seen <= 1'b1;
                done_cycle <= next_cycle;
            end
        end
    end

    initial begin
        logic [31:0] status;
        logic [31:0] ctrl;
        logic [31:0] len;
        logic [31:0] out0;
        logic [63:0] start_time;
        logic [63:0] end_time;
        int unsigned elapsed_cycles;
        int unsigned word_count;
        int unsigned total_cycles_e2e;
        int unsigned unified_active_cycles;
        real cycles_per_byte_unified;
        real throughput_mb_s_unified;
        real cycles_per_byte_e2e;
        real throughput_mb_s_e2e;

        rst_n = 1'b0;
        s_awaddr = 32'd0;
        s_awvalid = 1'b0;
        s_wdata = 32'd0;
        s_wstrb = 4'd0;
        s_wvalid = 1'b0;
        s_bready = 1'b0;
        s_araddr = 32'd0;
        s_arvalid = 1'b0;
        s_rready = 1'b0;

        $display("[TB][CFG] TB_PAYLOAD_BYTES=%0d", TB_PAYLOAD_BYTES);
        $display("[TB][CFG] TB_MAX_CYCLES=%0d", TB_MAX_CYCLES);

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("[TB][ASCON] Starting MMIO benchmark");
        $display("[TB][ASCON] Base address = 0x%08h", `SOC_ASCON_BASE);

        fill_message_words(TB_PAYLOAD_BYTES, word_count);

        axi_read(`SOC_ASCON_BASE + 32'h00, ctrl);
        axi_read(`SOC_ASCON_BASE + 32'h04, status);

        if (ctrl !== 32'd0) begin
            $fatal(1, "CTRL should be 0 before start, got 0x%08h", ctrl);
        end
        if (status !== 32'd0) begin
            $fatal(1, "STATUS should be IDLE before start, got %0d", status);
        end

        // End-to-end timing includes MMIO payload writes, LEN write, START write, and status polling.
        start_time = $time;
        for (int unsigned i = 0; i < word_count; i++) begin
            axi_write(`SOC_ASCON_BASE + 32'h10 + (i * 4), message_words[i]);
        end
        axi_write(`SOC_ASCON_BASE + 32'h08, TB_PAYLOAD_BYTES);
        axi_read(`SOC_ASCON_BASE + 32'h08, len);
        if (len !== TB_PAYLOAD_BYTES) begin
            $fatal(1, "LEN readback mismatch, expected %0d got %0d", TB_PAYLOAD_BYTES, len);
        end
        axi_write(`SOC_ASCON_BASE + 32'h00, 32'd1);

        wait_for_done(status, TB_MAX_CYCLES, elapsed_cycles);
        end_time = $time;

        axi_read(`SOC_ASCON_BASE + 32'h100, out0);

        total_cycles_e2e = int'((end_time - start_time) / 10);
        if (total_cycles_e2e == 0) begin
            $fatal(1, "Invalid end-to-end cycle count: 0");
        end
        if (!done_seen) begin
            $fatal(1, "Internal done cycle was not observed");
        end

        unified_active_cycles = done_cycle - first_accept_cycle;
        if (unified_active_cycles == 0) begin
            $fatal(1, "Invalid unified active cycle count: 0");
        end

        cycles_per_byte_unified = real'(TB_PAYLOAD_BYTES) / real'(unified_active_cycles);
        throughput_mb_s_unified = cycles_per_byte_unified * 100.0;
        cycles_per_byte_e2e = real'(TB_PAYLOAD_BYTES) / real'(total_cycles_e2e);
        throughput_mb_s_e2e = cycles_per_byte_e2e * 100.0;

        $display("[TB][ASCON] start_time=%0t first_accept_cycle=%0d done_cycle=%0d", start_time, first_accept_cycle, done_cycle);
        $display("[TB][ASCON][PERF_UNIFIED] bytes=%0d cycles=%0d cycles_per_byte=%0.2f throughput=%0.2f MB/s @100MHz", TB_PAYLOAD_BYTES, unified_active_cycles, cycles_per_byte_unified, throughput_mb_s_unified);
        $display("[TB][ASCON][PERF_E2E] bytes=%0d cycles=%0d cycles_per_byte=%0.2f throughput=%0.2f MB/s @100MHz", TB_PAYLOAD_BYTES, total_cycles_e2e, cycles_per_byte_e2e, throughput_mb_s_e2e);
        $display("[TB][ASCON] OUT0=0x%08h", out0);
        $display("[TB][ASCON] PASS");

        $finish;
    end

endmodule









