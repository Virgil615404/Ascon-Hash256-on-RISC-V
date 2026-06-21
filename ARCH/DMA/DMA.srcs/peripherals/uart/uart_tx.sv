// =========================
// UART TX Module
// =========================
module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 9600
)(
    input  logic       clk,
    input  logic       rst,
    output logic       tx,
    input  logic [7:0] data_in,
    input  logic       start,
    output logic       busy
);

    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11
    } state_t;

    state_t state;
    logic [15:0] clk_cnt;
    logic [2:0]  bit_idx;
    logic [7:0]  tx_shift;

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            clk_cnt <= '0;
            bit_idx <= '0;
            tx      <= 1'b1;
            busy    <= 1'b0;
            tx_shift <= '0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    busy <= 1'b0;
                    clk_cnt <= '0;
                    bit_idx <= '0;
                    if (start && !busy) begin
                        state <= START;
                        tx_shift <= data_in;
                        busy <= 1'b1;
                    end
                end
                START: begin
                    tx <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= '0;
                        state <= DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                DATA: begin
                    tx <= tx_shift[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= '0;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= '0;
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                STOP: begin
                    tx <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= '0;
                        state <= IDLE;
                        busy <= 1'b0;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule