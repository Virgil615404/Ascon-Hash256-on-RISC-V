`include "soc_addr_map.vh"
`include "../../peripherals/ascon/config.sv"

module axil_ascon_slave #(
    parameter IN_WORDS  = 16,
    parameter OUT_WORDS = 16
)(
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
    // Register map offsets (relative to SOC_ASCON_BASE)
    localparam CTRL_OFF = 32'h00;
    localparam STATUS_OFF= 32'h04;
    localparam LEN_OFF  = 32'h08;
    localparam IN_OFF   = 32'h10; // then word-aligned
    localparam OUT_OFF  = 32'h100;

    logic [31:0] awaddr_reg;
    logic [31:0] wdata_reg;
    logic [3:0]  wstrb_reg;
    logic        aw_captured;
    logic        w_captured;
    logic        bvalid_reg;

    logic [31:0] araddr_reg;
    logic        read_pending;
    logic [31:0] rdata_reg;
    logic        rvalid_reg;

    // Accelerator registers
    logic [31:0] reg_ctrl;   // bit0: START
    logic [31:0] reg_len;    // length in bytes
    logic [31:0] reg_status;

    (* ram_style = "block" *) logic [31:0] in_mem [IN_WORDS-1:0];
    (* ram_style = "block" *) logic [31:0] out_mem[OUT_WORDS-1:0];

    // accelerator control
    logic        acc_start_pulse;
    logic        acc_busy;
    logic        acc_done;

    // ascon core interface signals
    logic [CCW-1:0] bdi;
    logic [CCW/8-1:0] bdi_valid;
    logic bdi_ready;
    data_e bdi_type;
    logic bdi_eot;
    logic bdi_eoi;

    logic [CCW-1:0] bdo;
    logic bdo_valid;
    logic bdo_ready;
    data_e bdo_type;
    logic bdo_eot;
    logic bdo_eoo;
    logic done_int;

    assign bdo_eoo = 1'b0;

    integer i;

    // AXI-lite interface assignments
    assign s_axi_awready = !aw_captured;
    assign s_axi_wready  = !w_captured;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = bvalid_reg;

    assign s_axi_arready = !read_pending && !rvalid_reg;
    assign s_axi_rdata   = rdata_reg;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rvalid  = rvalid_reg;

    // address used for register access (offset)
    logic [31:0] reg_addr;
    assign reg_addr = (aw_captured && w_captured && !bvalid_reg) ? (awaddr_reg - `SOC_ASCON_BASE) : (araddr_reg - `SOC_ASCON_BASE);

    // AXI capture logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awaddr_reg   <= 32'd0;
            wdata_reg    <= 32'd0;
            wstrb_reg    <= 4'd0;
            aw_captured  <= 1'b0;
            w_captured   <= 1'b0;
            bvalid_reg   <= 1'b0;
            araddr_reg   <= 32'd0;
            read_pending <= 1'b0;
            rdata_reg    <= 32'd0;
            rvalid_reg   <= 1'b0;
            reg_ctrl     <= 32'd0;
            reg_len      <= 32'd0;
            for (i=0;i<IN_WORDS;i=i+1) in_mem[i] <= 32'd0;
            for (i=0;i<OUT_WORDS;i=i+1) out_mem[i] <= 32'd0;
        end else begin
            acc_start_pulse <= 1'b0;

            if (!aw_captured && s_axi_awvalid && s_axi_awready) begin
                awaddr_reg  <= s_axi_awaddr;
                aw_captured <= 1'b1;
            end

            if (!w_captured && s_axi_wvalid && s_axi_wready) begin
                wdata_reg  <= s_axi_wdata;
                wstrb_reg  <= s_axi_wstrb;
                w_captured <= 1'b1;
            end

            if (aw_captured && w_captured && !bvalid_reg) begin
                // perform write
                logic [31:0] off;
                off = awaddr_reg - `SOC_ASCON_BASE;
                if (off == CTRL_OFF) begin
                    reg_ctrl <= wdata_reg;
                    if (wdata_reg[0]) acc_start_pulse <= 1'b1;
                end else if (off == LEN_OFF) begin
                    reg_len <= wdata_reg;
                end else if ((off >= IN_OFF) && (off < OUT_OFF)) begin
                    int idx;
                    idx = (off - IN_OFF) >> 2;
                    if (idx < IN_WORDS) in_mem[idx] <= wdata_reg;
                end

                bvalid_reg    <= 1'b1;
                aw_captured   <= 1'b0;
                w_captured    <= 1'b0;
            end else if (bvalid_reg && s_axi_bready) begin
                bvalid_reg    <= 1'b0;
            end

            if (!read_pending && !rvalid_reg && s_axi_arvalid && s_axi_arready) begin
                araddr_reg    <= s_axi_araddr;
                read_pending  <= 1'b1;
            end

            if (read_pending) begin
                logic [31:0] off_r;
                off_r = araddr_reg - `SOC_ASCON_BASE;
                if (off_r == CTRL_OFF) rdata_reg <= reg_ctrl;
                else if (off_r == STATUS_OFF) rdata_reg <= reg_status;
                else if (off_r == LEN_OFF) rdata_reg <= reg_len;
                else if ((off_r >= IN_OFF) && (off_r < OUT_OFF)) begin
                    int idx_r;
                    idx_r = (off_r - IN_OFF) >> 2;
                    if (idx_r < IN_WORDS) rdata_reg <= in_mem[idx_r]; else rdata_reg <= 32'd0;
                end else if ((off_r >= OUT_OFF)) begin
                    int idx_r;
                    idx_r = (off_r - OUT_OFF) >> 2;
                    if (idx_r < OUT_WORDS) rdata_reg <= out_mem[idx_r]; else rdata_reg <= 32'd0;
                end else rdata_reg <= 32'd0;

                rvalid_reg    <= 1'b1;
                read_pending  <= 1'b0;
            end else if (rvalid_reg && s_axi_rready) begin
                rvalid_reg    <= 1'b0;
            end
        end
    end

    // Accelerator run control and data flow
    logic [31:0] total_words;
    logic [31:0] word_idx;
    logic [31:0] out_idx;
    logic feeding;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_busy <= 1'b0;
            acc_done <= 1'b0;
            total_words <= 32'd0;
            word_idx <= 32'd0;
            out_idx <= 32'd0;
            feeding <= 1'b0;
            bdo_ready <= 1'b0;
        end else begin
            bdo_ready <= 1'b0;
            if (acc_start_pulse && !acc_busy) begin
                // compute words from bytes (ceil)
                total_words <= (reg_len + 3) >> 2;
                word_idx <= 0;
                out_idx <= 0;
                acc_busy <= 1'b1;
                acc_done <= 1'b0;
                feeding <= 1'b1;
                $display("[ASCON] start len=%0d at %0t", reg_len, $time);
            end

            // feed input words to core
            if (acc_busy && feeding) begin
                if (word_idx < total_words) begin
                    logic last_word;
                    last_word = (word_idx == (total_words - 1));
                    bdi <= in_mem[word_idx];
                    // Full-word valid except for the last partial word, which may be 1-3 bytes.
                    if (last_word) begin
                        int unsigned bytes_this_word;
                        bytes_this_word = reg_len - (word_idx * 4);
                        if (bytes_this_word == 0 || bytes_this_word > 4) begin
                            bytes_this_word = 4;
                        end
                        bdi_valid <= '0;
                        for (int j = 0; j < (CCW/8); j++) begin
                            bdi_valid[j] <= (j < bytes_this_word);
                        end
                    end else begin
                        bdi_valid <= {(CCW/8){1'b1}};
                    end
                    bdi_type <= D_MSG;
                    bdi_eot <= last_word;
                    bdi_eoi <= last_word;
                    if (bdi_ready) begin
                        word_idx <= word_idx + 1;
                    end
                end else begin
                    feeding <= 1'b0;
                end
            end else begin
                bdi <= '0;
                bdi_valid <= '0;
                bdi_type <= D_MSG;
                bdi_eot <= 1'b0;
                bdi_eoi <= 1'b0;
            end

            // capture outputs
            if (bdo_valid) begin
                if (out_idx < OUT_WORDS) out_mem[out_idx] <= bdo;
                out_idx <= out_idx + 1;
                bdo_ready <= 1'b1; // always accept
            end

            // done handshake
            if (done_int) begin
                acc_busy <= 1'b0;
                acc_done <= 1'b1;
                $display("[ASCON] done at %0t", $time);
            end

            if (acc_done && (reg_ctrl[0] == 1'b0)) begin
                // user cleared start bit -> clear done
                acc_done <= 1'b0;
            end
        end
    end

    assign reg_status = acc_busy ? 32'd1 : (acc_done ? 32'd2 : 32'd0);

    // instantiate ascon core
    ascon_core u_ascon_core (
        .clk(clk), .rst(~rst_n),
        .bdi(bdi), .bdi_valid(bdi_valid), .bdi_ready(bdi_ready),
        .bdi_type(bdi_type), .bdi_eot(bdi_eot), .bdi_eoi(bdi_eoi),
        .mode(M_HASH256),
        .bdo(bdo), .bdo_valid(bdo_valid), .bdo_ready(bdo_ready),
        .bdo_type(bdo_type), .bdo_eot(bdo_eot), .bdo_eoo(bdo_eoo),
        .done(done_int)
    );

endmodule
