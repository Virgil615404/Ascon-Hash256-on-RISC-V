// =========================
// UART RX Module
// =========================
module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 9600
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       rx,
    output logic [7:0] data_out,
    output logic       valid
);

    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam integer HALF_CLKS    = CLKS_PER_BIT / 2;

    // State machine with enum for better readability
    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11
    } state_t;

    state_t state;
    logic [15:0] clk_cnt;
    logic [2:0]  bit_idx;
    logic [7:0]  rx_shift;

    always_ff @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            clk_cnt   <= '0;
            bit_idx   <= '0;
            data_out  <= '0;
            valid     <= 1'b0;
            rx_shift  <= '0;
        end else begin
            valid <= 1'b0;  // Default assignment
            
            case (state)
                IDLE: begin
                    clk_cnt <= '0;
                    bit_idx <= '0;
                    if (~rx) state <= START;
                end
                START: begin
                    if (clk_cnt == HALF_CLKS) begin
                        clk_cnt <= '0;
                        state <= DATA;
                        bit_idx <= '0;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                DATA: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= '0;
                        rx_shift[bit_idx] <= rx;
                        if (bit_idx == 3'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                STOP: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= '0;
                        state <= IDLE;
                        if (rx) begin
                            data_out <= rx_shift;
                            valid <= 1'b1;
                        end
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