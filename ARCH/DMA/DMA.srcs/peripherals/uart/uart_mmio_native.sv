module uart_mmio_native #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 9600
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        we,
    input  logic        re,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,

    input  logic        uart_rx_i,
    output logic        uart_tx_o
);
    localparam logic [31:0] REG_TXDATA = 32'h0000_0000;
    localparam logic [31:0] REG_RXDATA = 32'h0000_0004;
    localparam logic [31:0] REG_STATUS = 32'h0000_0008;

    logic [7:0] tx_data;
    logic       tx_start;
    logic       tx_busy;

    logic [7:0] rx_data_wire;
    logic       rx_valid_wire;

    logic [7:0] rx_data_latched;
    logic       rx_valid_latched;

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_tx (
        .clk    (clk),
        .rst    (~rst_n),
        .tx     (uart_tx_o),
        .data_in(tx_data),
        .start  (tx_start),
        .busy   (tx_busy)
    );

    uart_rx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_rx (
        .clk     (clk),
        .rst     (~rst_n),
        .rx      (uart_rx_i),
        .data_out(rx_data_wire),
        .valid   (rx_valid_wire)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_data         <= 8'h00;
            tx_start        <= 1'b0;
            rx_data_latched <= 8'h00;
            rx_valid_latched<= 1'b0;
        end else begin
            tx_start <= 1'b0;

            if (rx_valid_wire) begin
                rx_data_latched  <= rx_data_wire;
                rx_valid_latched <= 1'b1;
            end

            if (we && (addr == REG_TXDATA) && !tx_busy) begin
                tx_data  <= wdata[7:0];
                tx_start <= 1'b1;
            end

            if (re && (addr == REG_RXDATA)) begin
                rx_valid_latched <= 1'b0;
            end
        end
    end

    always_comb begin
        unique case (addr)
            REG_TXDATA: rdata = {24'h0, tx_data};
            REG_RXDATA: rdata = {24'h0, rx_data_latched};
            REG_STATUS: rdata = {30'h0, rx_valid_latched, tx_busy};
            default:    rdata = 32'h0000_0000;
        endcase
    end
endmodule
