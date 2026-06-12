module l1_icache #(
    parameter LINES = 64
)(
    input         clk,
    input         rst_n,

    input         cpu_valid,
    input  [9:0]  cpu_addr,
    output        cpu_ready,
    output [31:0] cpu_rdata,

    output        mem_valid,
    output [9:0]  mem_addr,
    input         mem_ready,
    input  [31:0] mem_rdata
);
    localparam ST_IDLE = 1'b0;
    localparam ST_MISS = 1'b1;

    reg state;
    reg [9:0] miss_addr;
    reg [31:0] miss_rdata;
    reg miss_ready_pulse;

    reg [31:0] data_mem [0:LINES-1];
    reg [1:0]  tag_mem  [0:LINES-1];
    reg        valid_mem[0:LINES-1];

    integer i;

    wire [5:0] cpu_idx = cpu_addr[7:2];
    wire [1:0] cpu_tag = cpu_addr[9:8];
    wire       hit = valid_mem[cpu_idx] && (tag_mem[cpu_idx] == cpu_tag);

    wire [5:0] miss_idx = miss_addr[7:2];
    wire [1:0] miss_tag = miss_addr[9:8];

    assign cpu_ready = ((state == ST_IDLE) && cpu_valid && hit) || miss_ready_pulse;
    assign cpu_rdata = ((state == ST_IDLE) && cpu_valid && hit) ? data_mem[cpu_idx] : miss_rdata;

    assign mem_valid = (state == ST_MISS);
    assign mem_addr  = miss_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            miss_addr <= 10'd0;
            miss_rdata <= 32'd0;
            miss_ready_pulse <= 1'b0;
            for (i = 0; i < LINES; i = i + 1) begin
                valid_mem[i] <= 1'b0;
                tag_mem[i] <= 2'd0;
                data_mem[i] <= 32'd0;
            end
        end else begin
            miss_ready_pulse <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (cpu_valid && !hit) begin
                        miss_addr <= {cpu_addr[9:2], 2'b00};
                        state <= ST_MISS;
                    end
                end

                ST_MISS: begin
                    if (mem_ready) begin
                        data_mem[miss_idx] <= mem_rdata;
                        tag_mem[miss_idx] <= miss_tag;
                        valid_mem[miss_idx] <= 1'b1;
                        miss_rdata <= mem_rdata;
                        miss_ready_pulse <= 1'b1;
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
