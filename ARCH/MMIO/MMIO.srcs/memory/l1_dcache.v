module l1_dcache #(
    parameter LINES = 64
)(
    input         clk,
    input         rst_n,

    input         cpu_valid,
    input         cpu_we,
    input  [2:0]  cpu_size,
    input  [31:0] cpu_addr,
    input  [31:0] cpu_wdata,
    output        cpu_ready,
    output [31:0] cpu_rdata,

    output        mem_valid,
    output        mem_we,
    output [31:0] mem_addr,
    output [31:0] mem_wdata,
    input         mem_ready,
    input  [31:0] mem_rdata
);
    localparam ST_IDLE   = 2'd0;
    localparam ST_WB     = 2'd1;
    localparam ST_REFILL = 2'd2;

    reg [1:0] state;
    reg [31:0] req_addr;
    reg [31:0] req_wdata;
    reg req_we;

    reg [31:0] done_rdata;
    reg done_ready_pulse;

    (* ram_style = "block" *) reg [31:0] data_mem [0:LINES-1];
    (* ram_style = "block" *) reg [23:0] tag_mem  [0:LINES-1];
    (* ram_style = "block" *) reg        valid_mem[0:LINES-1];
    (* ram_style = "block" *) reg        dirty_mem[0:LINES-1];

    reg [31:0] wb_addr;
    reg [31:0] wb_wdata;
    reg [2:0]  req_size;

    integer i;

    wire [5:0]  cpu_idx = cpu_addr[7:2];
    wire [23:0] cpu_tag = cpu_addr[31:8];
    wire cpu_hit = valid_mem[cpu_idx] && (tag_mem[cpu_idx] == cpu_tag);
    wire read_hit = cpu_valid && !cpu_we && cpu_hit;
    wire write_hit = cpu_valid && cpu_we && cpu_hit;

    wire cpu_need_wb = valid_mem[cpu_idx] && dirty_mem[cpu_idx] && (tag_mem[cpu_idx] != cpu_tag);
    wire [31:0] cpu_victim_addr = {tag_mem[cpu_idx], cpu_idx, 2'b00};

    wire [5:0]  req_idx = req_addr[7:2];
    wire [23:0] req_tag = req_addr[31:8];

    function [31:0] merge_store_word;
        input [31:0] old_word;
        input [31:0] new_word;
        input [2:0]  size;
        input [1:0]  byte_sel;
        reg [31:0] merged;
        begin
            merged = old_word;
            case (size)
                3'b000: begin
                    case (byte_sel)
                        2'b00: merged[7:0]   = new_word[7:0];
                        2'b01: merged[15:8]  = new_word[7:0];
                        2'b10: merged[23:16] = new_word[7:0];
                        default: merged[31:24] = new_word[7:0];
                    endcase
                end
                3'b001: begin
                    if (byte_sel[1] == 1'b0) begin
                        merged[15:0] = new_word[15:0];
                    end else begin
                        merged[31:16] = new_word[15:0];
                    end
                end
                default: begin
                    merged = new_word;
                end
            endcase
            merge_store_word = merged;
        end
    endfunction

    assign cpu_ready = read_hit || write_hit || done_ready_pulse;
    assign cpu_rdata = read_hit ? data_mem[cpu_idx] : done_rdata;

    assign mem_valid = (state == ST_WB) || (state == ST_REFILL);
    assign mem_we    = (state == ST_WB);
    assign mem_addr  = (state == ST_WB) ? wb_addr : req_addr;
    assign mem_wdata = wb_wdata;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            req_addr <= 32'd0;
            req_wdata <= 32'd0;
            req_we <= 1'b0;
            done_rdata <= 32'd0;
            done_ready_pulse <= 1'b0;
            for (i = 0; i < LINES; i = i + 1) begin
                valid_mem[i] <= 1'b0;
                tag_mem[i] <= 24'd0;
                data_mem[i] <= 32'd0;
                dirty_mem[i] <= 1'b0;
            end
            wb_addr <= 32'd0;
            wb_wdata <= 32'd0;
        end else begin
            done_ready_pulse <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (cpu_valid) begin
                        if (write_hit) begin
                            data_mem[cpu_idx] <= merge_store_word(data_mem[cpu_idx], cpu_wdata, cpu_size, cpu_addr[1:0]);
                            dirty_mem[cpu_idx] <= 1'b1;
                        end else if (!cpu_we && read_hit) begin
                            // read hit is served combinationally
                        end else begin
                            req_addr <= {cpu_addr[31:2], 2'b00};
                            req_wdata <= cpu_wdata;
                            req_size <= cpu_size;
                            req_we <= cpu_we;
                            if (cpu_need_wb) begin
                                wb_addr <= cpu_victim_addr;
                                wb_wdata <= data_mem[cpu_idx];
                                state <= ST_WB;
                            end else begin
                                state <= ST_REFILL;
                            end
                        end
                    end
                end

                ST_WB: begin
                    if (mem_ready) begin
                        state <= ST_REFILL;
                    end
                end

                ST_REFILL: begin
                    if (mem_ready) begin
                        data_mem[req_idx] <= mem_rdata;
                        tag_mem[req_idx] <= req_tag;
                        valid_mem[req_idx] <= 1'b1;
                        if (req_we) begin
                            data_mem[req_idx] <= merge_store_word(mem_rdata, req_wdata, req_size, req_addr[1:0]);
                            dirty_mem[req_idx] <= 1'b1;
                            done_ready_pulse <= 1'b1;
                        end else begin
                            dirty_mem[req_idx] <= 1'b0;
                            done_rdata <= mem_rdata;
                            done_ready_pulse <= 1'b1;
                        end
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
