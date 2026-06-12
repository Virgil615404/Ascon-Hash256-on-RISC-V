module cpu_native_to_axil(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        dmem_valid,
    input  logic        dmem_we,
    input  logic [31:0] dmem_addr,
    input  logic [31:0] dmem_wdata,
    output logic        dmem_ready,
    output logic [31:0] dmem_rdata,

    // AXI-Lite master write address
    output logic [31:0] m_axi_awaddr,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,

    // AXI-Lite master write data
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,

    // AXI-Lite master write response
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,

    // AXI-Lite master read address
    output logic [31:0] m_axi_araddr,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,

    // AXI-Lite master read data
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);
    typedef enum logic [2:0] {
        ST_IDLE      = 3'd0,
        ST_WR_REQ    = 3'd1,
        ST_WR_RESP   = 3'd2,
        ST_RD_REQ    = 3'd3,
        ST_RD_RESP   = 3'd4
    } state_t;

    state_t state;

    logic [31:0] req_addr;
    logic [31:0] req_wdata;
    logic        req_we;

    logic aw_done;
    logic w_done;

    logic [31:0] dmem_rdata_reg;
    logic        dmem_ready_reg;

    assign dmem_rdata = dmem_rdata_reg;
    assign dmem_ready = dmem_ready_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            req_addr       <= 32'd0;
            req_wdata      <= 32'd0;
            req_we         <= 1'b0;
            aw_done        <= 1'b0;
            w_done         <= 1'b0;
            dmem_rdata_reg <= 32'd0;
            dmem_ready_reg <= 1'b0;
        end else begin
            dmem_ready_reg <= 1'b0;

            case (state)
                ST_IDLE: begin
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;
                    if (dmem_valid) begin
                        req_addr  <= dmem_addr;
                        req_wdata <= dmem_wdata;
                        req_we    <= dmem_we;
                        if (dmem_we) begin
                            state <= ST_WR_REQ;
                        end else begin
                            state <= ST_RD_REQ;
                        end
                    end
                end

                ST_WR_REQ: begin
                    if (!aw_done && m_axi_awready) aw_done <= 1'b1;
                    if (!w_done  && m_axi_wready)  w_done  <= 1'b1;

                    if ((aw_done || m_axi_awready) && (w_done || m_axi_wready)) begin
                        if (m_axi_bvalid) begin
                            dmem_ready_reg <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            state <= ST_WR_RESP;
                        end
                    end
                end

                ST_WR_RESP: begin
                    if (m_axi_bvalid) begin
                        dmem_ready_reg <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                ST_RD_REQ: begin
                    if (m_axi_arready) begin
                        if (m_axi_rvalid) begin
                            dmem_rdata_reg <= m_axi_rdata;
                            dmem_ready_reg <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            state <= ST_RD_RESP;
                        end
                    end
                end

                ST_RD_RESP: begin
                    if (m_axi_rvalid) begin
                        dmem_rdata_reg <= m_axi_rdata;
                        dmem_ready_reg <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    always_comb begin
        m_axi_awaddr  = req_addr;
        m_axi_awvalid = (state == ST_WR_REQ) && !aw_done;

        m_axi_wdata   = req_wdata;
        m_axi_wstrb   = 4'b1111;
        m_axi_wvalid  = (state == ST_WR_REQ) && !w_done;

        m_axi_bready  = (state == ST_WR_REQ) || (state == ST_WR_RESP);

        m_axi_araddr  = req_addr;
        m_axi_arvalid = (state == ST_RD_REQ);

        m_axi_rready  = (state == ST_RD_REQ) || (state == ST_RD_RESP);
    end
endmodule
