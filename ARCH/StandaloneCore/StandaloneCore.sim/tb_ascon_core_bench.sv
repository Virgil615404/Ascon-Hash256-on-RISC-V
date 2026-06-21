`timescale 1ns/1ps
`include "../StandaloneCore.srcs/peripherals/asconhash256/config.sv"

module tb_ascon_core_bench;
    localparam int MAX_WORDS = 2048;
    localparam int TB_PAYLOAD_BYTES = 1;
    localparam int TB_MAX_CYCLES = 50000;

    logic clk;
    logic rst;

    logic [CCW-1:0]     bdi;
    logic [CCW/8-1:0]   bdi_valid;
    logic               bdi_ready;
    data_e              bdi_type;
    logic               bdi_eot;
    logic               bdi_eoi;
    mode_e              mode;
    logic [CCW-1:0]     bdo;
    logic               bdo_valid;
    logic               bdo_ready;
    data_e              bdo_type;
    logic               bdo_eot;
    logic               bdo_eoo;
    logic               done;

    int unsigned cycle_count;
    int unsigned first_accept_cycle;
    int unsigned done_cycle;
    int unsigned bench_start_cycle;
    int unsigned word_count;

    bit first_accept_seen;
    bit done_seen;
    bit digest_seen;

    logic [CCW-1:0] digest0_value;
    logic [CCW-1:0] message_words [0:MAX_WORDS-1];

    always #5 clk = ~clk;

    ascon_core dut (
        .clk      (clk),
        .rst      (rst),
        .bdi      (bdi),
        .bdi_valid(bdi_valid),
        .bdi_ready(bdi_ready),
        .bdi_type (bdi_type),
        .bdi_eot  (bdi_eot),
        .bdi_eoi  (bdi_eoi),
        .mode     (mode),
        .bdo      (bdo),
        .bdo_valid(bdo_valid),
        .bdo_ready(bdo_ready),
        .bdo_type (bdo_type),
        .bdo_eot  (bdo_eot),
        .bdo_eoo  (bdo_eoo),
        .done     (done)
    );

    function automatic logic [CCW-1:0] make_word(input int unsigned word_index);
        logic [CCW-1:0] word;
        int unsigned byte_base;
        begin
            word = '0;
            byte_base = word_index * (CCW / 8);
            for (int i = 0; i < (CCW / 8); i++) begin
                word[((CCW / 8 - 1 - i) * 8) +: 8] = 8'(byte_base + i);
            end
            return word;
        end
    endfunction

    function automatic logic [CCW/8-1:0] make_valid_mask(input int unsigned valid_bytes);
        logic [CCW/8-1:0] mask;
        begin
            mask = '0;
            for (int i = 0; i < (CCW / 8); i++) begin
                mask[i] = (i < valid_bytes);
            end
            return mask;
        end
    endfunction

    task automatic send_word(
        input logic [CCW-1:0] data,
        input logic [CCW/8-1:0] valid_mask,
        input bit last_word
    );
        begin
            bdi      = data;
            bdi_valid = valid_mask;
            bdi_type  = D_MSG;
            bdi_eot   = last_word;
            bdi_eoi   = last_word;

            do begin
                @(posedge clk);
            end while (!bdi_ready);

            @(negedge clk);
            bdi_valid = '0;
            bdi_eot   = 1'b0;
            bdi_eoi   = 1'b0;
        end
    endtask

    task automatic init_message(input int unsigned payload_bytes);
        int unsigned bytes_per_word;
        begin
            bytes_per_word = CCW / 8;
            word_count = (payload_bytes + bytes_per_word - 1) / bytes_per_word;
            if (word_count == 0) begin
                $fatal(1, "TB_PAYLOAD_BYTES must be non-zero");
            end
            if (word_count > MAX_WORDS) begin
                $fatal(1, "TB_PAYLOAD_BYTES too large for this bench: %0d", payload_bytes);
            end
            for (int unsigned i = 0; i < word_count; i++) begin
                message_words[i] = make_word(i);
            end
        end
    endtask

    always_ff @(posedge clk or posedge rst) begin
        int unsigned next_cycle;
        int unsigned bytes_per_word;
        int unsigned current_word;

        if (rst) begin
            cycle_count        <= 0;
            first_accept_seen  <= 0;
            done_seen          <= 0;
            digest_seen        <= 0;
            first_accept_cycle <= 0;
            done_cycle         <= 0;
            digest0_value      <= '0;
        end else begin
            next_cycle = cycle_count + 1;
            cycle_count <= next_cycle;

            if (!first_accept_seen && bdi_ready && (|bdi_valid) && (bdi_type == D_MSG)) begin
                first_accept_seen  <= 1;
                first_accept_cycle <= next_cycle;
            end

            if (!digest_seen && bdo_valid && bdo_ready) begin
                digest_seen   <= 1;
                digest0_value <= bdo;
            end

            if (!done_seen && done) begin
                done_seen  <= 1;
                done_cycle <= next_cycle;
            end
        end
    end

    initial begin
        int unsigned bytes_per_word;
        int unsigned active_cycles_unified;
        int unsigned active_cycles_e2e;
        real bytes_per_cycle_unified;
        real throughput_mb_s_unified;
        real bytes_per_cycle_e2e;
        real throughput_mb_s_e2e;

        clk = 1'b0;
        rst = 1'b1;

        bdi        = '0;
        bdi_valid  = '0;
        bdi_type   = D_MSG;
        bdi_eot    = 1'b0;
        bdi_eoi    = 1'b0;
        mode       = M_INVALID;
        bdo_ready  = 1'b1;

        $display("[TB][CFG] TB_PAYLOAD_BYTES=%0d", TB_PAYLOAD_BYTES);
        $display("[TB][CFG] TB_MAX_CYCLES=%0d", TB_MAX_CYCLES);

        $display("[TB][CFG] UROL=%0d CCW=%0d", UROL, CCW);
        init_message(TB_PAYLOAD_BYTES);

        repeat (5) @(posedge clk);
        rst = 1'b0;
        mode = M_HASH256;
        repeat (2) @(posedge clk);

        $display("[TB][CORE] Starting standalone core benchmark");
        $display("[TB][CORE] payload=%0d bytes words=%0d", TB_PAYLOAD_BYTES, word_count);

        bench_start_cycle = cycle_count;

        bytes_per_word = CCW / 8;
        for (int unsigned i = 0; i < word_count; i++) begin
            int unsigned valid_bytes;
            logic [CCW/8-1:0] valid_mask;
            bit last_word;

            valid_bytes = ((i + 1) * bytes_per_word <= TB_PAYLOAD_BYTES) ? bytes_per_word : (TB_PAYLOAD_BYTES - i * bytes_per_word);
            valid_mask = make_valid_mask(valid_bytes);
            last_word = (i == (word_count - 1));

            send_word(message_words[i], valid_mask, last_word);
        end

        while (!done_seen && (cycle_count < TB_MAX_CYCLES)) begin
            @(posedge clk);
        end

        if (!done_seen) begin
            $fatal(1, "Standalone core did not finish within %0d cycles", TB_MAX_CYCLES);
        end

        active_cycles_unified = done_cycle - first_accept_cycle;
        active_cycles_e2e = done_cycle - bench_start_cycle;
        if (active_cycles_unified == 0) begin
            $fatal(1, "Invalid unified active cycle count: 0");
        end
        if (active_cycles_e2e == 0) begin
            $fatal(1, "Invalid end-to-end cycle count: 0");
        end

        bytes_per_cycle_unified = real'(TB_PAYLOAD_BYTES) / real'(active_cycles_unified);
        throughput_mb_s_unified = bytes_per_cycle_unified * 100.0;
        bytes_per_cycle_e2e = real'(TB_PAYLOAD_BYTES) / real'(active_cycles_e2e);
        throughput_mb_s_e2e = bytes_per_cycle_e2e * 100.0;

        $display("[TB][CORE] bench_start_cycle=%0d first_accept_cycle=%0d done_cycle=%0d", bench_start_cycle, first_accept_cycle, done_cycle);
        $display("[TB][CORE][PERF_UNIFIED] bytes=%0d cycles=%0d bytes_per_cycle=%0.2f throughput=%0.2f MB/s @100MHz", TB_PAYLOAD_BYTES, active_cycles_unified, bytes_per_cycle_unified, throughput_mb_s_unified);
        $display("[TB][CORE][PERF_E2E] bytes=%0d cycles=%0d bytes_per_cycle=%0.2f throughput=%0.2f MB/s @100MHz", TB_PAYLOAD_BYTES, active_cycles_e2e, bytes_per_cycle_e2e, throughput_mb_s_e2e);
        $display("[TB][CORE] DIGEST0=0x%08h", digest0_value);
        $display("[TB][CORE] PASS");

        $finish;
    end
endmodule










