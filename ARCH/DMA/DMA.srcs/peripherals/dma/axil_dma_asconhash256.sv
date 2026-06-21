`include "soc_addr_map.vh"
`include "../asconhash256/config.sv"

module axil_dma_asconhash256(
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
    input  logic        s_axi_rready,

    // RAM DMA read port
    output logic [31:0] ram_dma_addr,
    input  logic [31:0] ram_dma_rdata
);
    localparam logic [31:0] REG_CTRL    = 32'h0000_0000;
    localparam logic [31:0] REG_SRC     = 32'h0000_0004;
    localparam logic [31:0] REG_LEN     = 32'h0000_0008;
    localparam logic [31:0] REG_STATUS  = 32'h0000_000C;
    localparam logic [31:0] REG_DIGEST0 = 32'h0000_0010;
    localparam int          BYTES_PER_WORD = CCW / 8;
    localparam int          DIGEST_WORDS   = 256 / CCW;
    localparam int          DIGEST_IDX_W   = (DIGEST_WORDS <= 1) ? 1 : $clog2(DIGEST_WORDS);

    typedef enum logic [1:0] {
        ST_IDLE = 2'd0,
        ST_FEED = 2'd1,
        ST_WAIT = 2'd2
    } state_t;

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

    logic [31:0] src_addr_reg;
    logic [31:0] src_addr_run_reg;
    logic        dma_data_valid;
    logic [31:0] len_bytes_reg;
    logic [31:0] bytes_left_reg;
    logic        busy_reg;
    logic        done_reg;
    logic        error_reg;
    logic        empty_message_reg;
    logic [DIGEST_IDX_W-1:0] digest_write_idx;
    logic [31:0] digest_reg [0:DIGEST_WORDS-1];

    logic [CCW-1:0] bdi_word;
    logic [CCW/8-1:0] bdi_valid_mask;
    logic             bdi_ready;
    logic [CCW-1:0]   bdo_word;
    logic             bdo_valid;
    logic             bdo_ready;
    data_e            bdi_type;
    data_e            bdo_type_core;  // Receive from ascon_core
    logic             bdi_eot;
    logic             bdi_eoi;
    logic             bdo_eot;
    logic             bdo_eoo;
    logic             core_done;
    mode_e            mode;

    state_t state;

    function automatic logic [31:0] read_reg_value(input logic [31:0] addr);
        logic [31:0] offset;
        logic [31:0] digest_index;
        begin
            offset = addr - `SOC_DMA_ASCON_BASE;
            unique case (offset)
                REG_CTRL:   read_reg_value = {30'h0, error_reg, done_reg};
                REG_SRC:    read_reg_value = src_addr_reg;
                REG_LEN:    read_reg_value = len_bytes_reg;
                REG_STATUS: read_reg_value = {29'h0, error_reg, done_reg, busy_reg};
                default: begin
                    if ((offset >= REG_DIGEST0) && (offset < (REG_DIGEST0 + DIGEST_WORDS*4))) begin
                        digest_index = (offset - REG_DIGEST0) >> 2;
                        read_reg_value = digest_reg[digest_index];
                    end else begin
                        read_reg_value = 32'h0000_0000;
                    end
                end
            endcase
        end
    endfunction

    assign bdi_type = D_MSG;
    assign mode     = busy_reg ? M_HASH256 : M_INVALID;
    assign bdo_ready = busy_reg && (bytes_left_reg == 0);
    assign bdo_eoo   = 1'b0;

    generate
        if (CCW == 32) begin : gen_bdi_word_32
            assign bdi_word = ram_dma_rdata;
        end else begin : gen_bdi_word_wide
            assign bdi_word = {{(CCW-32){1'b0}}, ram_dma_rdata};
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awaddr_reg        <= 32'd0;
            wdata_reg         <= 32'd0;
            wstrb_reg         <= 4'd0;
            aw_captured       <= 1'b0;
            w_captured        <= 1'b0;
            bvalid_reg        <= 1'b0;
            araddr_reg        <= 32'd0;
            read_pending      <= 1'b0;
            rdata_reg         <= 32'd0;
            rvalid_reg        <= 1'b0;
            src_addr_reg      <= 32'd0;
            src_addr_run_reg  <= 32'd0;
            dma_data_valid    <= 1'b0;
            len_bytes_reg     <= 32'd0;
            bytes_left_reg    <= 32'd0;
            busy_reg          <= 1'b0;
            done_reg          <= 1'b0;
            error_reg         <= 1'b0;
            empty_message_reg <= 1'b0;
            digest_write_idx  <= '0;
            state             <= ST_IDLE;
            ram_dma_addr      <= 32'd0;
            for (int i = 0; i < DIGEST_WORDS; i++) begin
                digest_reg[i] <= 32'd0;
            end
        end else begin
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
                unique case (awaddr_reg - `SOC_DMA_ASCON_BASE)
                    REG_CTRL: begin
                        if (wdata_reg[0] && !busy_reg) begin
                            busy_reg          <= 1'b1;
                            done_reg          <= 1'b0;
                            error_reg         <= 1'b0;
                            bytes_left_reg    <= len_bytes_reg;
                            src_addr_run_reg  <= src_addr_reg;
                            dma_data_valid    <= 1'b0;
                            digest_write_idx  <= '0;
                            empty_message_reg <= (len_bytes_reg == 0);
                            state             <= (len_bytes_reg == 0) ? ST_WAIT : ST_FEED;
                            ram_dma_addr      <= src_addr_reg;
                        end
                    end
                    REG_SRC: begin
                        if (!busy_reg) src_addr_reg <= wdata_reg;
                    end
                    REG_LEN: begin
                        if (!busy_reg) len_bytes_reg <= wdata_reg;
                    end
                    default: begin
                    end
                endcase

                bvalid_reg  <= 1'b1;
                aw_captured <= 1'b0;
                w_captured  <= 1'b0;
            end else if (bvalid_reg && s_axi_bready) begin
                bvalid_reg <= 1'b0;
            end

            if (!read_pending && !rvalid_reg && s_axi_arvalid && s_axi_arready) begin
                araddr_reg   <= s_axi_araddr;
                read_pending <= 1'b1;
            end

            if (read_pending) begin
                rdata_reg    <= read_reg_value(araddr_reg);
                rvalid_reg   <= 1'b1;
                read_pending <= 1'b0;
            end else if (rvalid_reg && s_axi_rready) begin
                rvalid_reg <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    ram_dma_addr   <= src_addr_reg;
                    dma_data_valid <= 1'b0;
                end

                ST_FEED: begin
                    busy_reg     <= 1'b1;
                    ram_dma_addr <= src_addr_run_reg;

                    if (!dma_data_valid) begin
                        dma_data_valid <= 1'b1;
                    end else if (bdi_ready) begin
                        if (bytes_left_reg <= BYTES_PER_WORD) begin
                            bytes_left_reg <= 32'd0;
                            state          <= ST_WAIT;
                        end else begin
                            bytes_left_reg   <= bytes_left_reg - BYTES_PER_WORD;
                            src_addr_run_reg <= src_addr_run_reg + BYTES_PER_WORD;
                            ram_dma_addr     <= src_addr_run_reg + BYTES_PER_WORD;
                        end
                    end
                end

                ST_WAIT: begin
                    busy_reg     <= 1'b1;
                    ram_dma_addr <= src_addr_run_reg;
                    dma_data_valid <= 1'b0;

                    if (core_done) begin
                        busy_reg          <= 1'b0;
                        done_reg          <= 1'b1;
                        empty_message_reg <= 1'b0;
                        state             <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase

            if (bdo_valid && bdo_ready && (digest_write_idx < DIGEST_WORDS)) begin
                digest_reg[digest_write_idx] <= bdo_word;
                digest_write_idx <= digest_write_idx + 1'b1;
            end
        end
    end

    always_comb begin
        logic [CCW/8-1:0] valid_mask;
        int unsigned bytes_this_word;

        valid_mask = '0;
        bytes_this_word = 0;

        if ((state == ST_FEED) && dma_data_valid) begin
            bytes_this_word = (bytes_left_reg >= BYTES_PER_WORD) ? BYTES_PER_WORD : bytes_left_reg;
            if (bytes_this_word == 0) begin
                bytes_this_word = BYTES_PER_WORD;
            end
            for (int i = 0; i < BYTES_PER_WORD; i++) begin
                valid_mask[i] = (i < bytes_this_word);
            end
        end

        bdi_valid_mask = valid_mask;
        bdi_eot        = (state == ST_FEED) && dma_data_valid && (bytes_left_reg <= BYTES_PER_WORD);
        // Signal end-of-input on the last data beat for non-empty messages;
        // keep the existing empty-message pulse in ST_WAIT.
        bdi_eoi        = ((state == ST_FEED) && dma_data_valid && (bytes_left_reg <= BYTES_PER_WORD)) ||
                 ((state == ST_WAIT) && empty_message_reg);

        s_axi_awready = !aw_captured;
        s_axi_wready  = !w_captured;
        s_axi_bresp   = 2'b00;
        s_axi_bvalid  = bvalid_reg;

        s_axi_arready = !read_pending && !rvalid_reg;
        s_axi_rdata   = rdata_reg;
        s_axi_rresp   = 2'b00;
        s_axi_rvalid  = rvalid_reg;

        if (state == ST_FEED && bytes_left_reg == 0) begin
            bdi_valid_mask = '0;
        end
    end

    ascon_core u_ascon_core (
        .clk      (clk),
        .rst      (~rst_n),
        .bdi      (bdi_word),
        .bdi_valid(bdi_valid_mask),
        .bdi_ready(bdi_ready),
        .bdi_type (bdi_type),
        .bdi_eot  (bdi_eot),
        .bdi_eoi  (bdi_eoi),
        .mode     (mode),
        .bdo      (bdo_word),
        .bdo_valid(bdo_valid),
        .bdo_ready(bdo_ready),
        .bdo_type (bdo_type_core),
        .bdo_eot  (bdo_eot),
        .bdo_eoo  (bdo_eoo),
        .done     (core_done)
    );
endmodule