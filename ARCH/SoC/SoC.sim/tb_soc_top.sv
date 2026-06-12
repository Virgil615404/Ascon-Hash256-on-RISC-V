`timescale 1ns / 1ps

module tb_soc_top;
    reg clk;
    reg rst_n;
    reg uart_rx_i;

    wire uart_tx_o;
    wire [31:0] dbg_instr;
    wire [9:0]  dbg_pc;
    wire [31:0] dbg_alu;
    wire [4:0]  dbg_rd;

    integer max_cycles;
    integer cycle_count;
    integer halt_count;
    integer halt_marker_count;
    integer loop4_count;
    reg [9:0] last_pc;
    reg [9:0] last_pc2;
    reg [9:0] last_pc3;
    reg [9:0] last_pc4;

    soc_top #(
        .IMEM_HEX_FILE("D:/FPGA/RISC_V_CPU_PIPELINE/programs/_current.hex")
    ) u_top (
        .clk      (clk),
        .rst_n    (rst_n),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o),
        .dbg_instr(dbg_instr),
        .dbg_pc   (dbg_pc),
        .dbg_alu  (dbg_alu),
        .dbg_rd   (dbg_rd)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        uart_rx_i = 1'b1;
        max_cycles = 1000;
        cycle_count = 0;
        halt_count = 0;
        halt_marker_count = 0;
        loop4_count = 0;
        last_pc = 10'd0;
        last_pc2 = 10'd0;
        last_pc3 = 10'd0;
        last_pc4 = 10'd0;

        #40;
        rst_n = 1'b1;

        while (cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            if ($test$plusargs("TB_TRACE") && (cycle_count <= 80)) begin
                $strobe("[TB][TRACE] cycle=%0d pc=0x%0h instr=0x%08h branch_ex=%b branch_taken_ex=%b branch_taken_mem=%b", cycle_count, dbg_pc, dbg_instr, u_top.u_cpu.branch_ex, u_top.u_cpu.branch_taken_ex, u_top.u_cpu.branch_taken_mem);
            end

            // Convention: a stable beq x0,x0,0 (0x00000063) indicates program end.
            if ((dbg_instr == 32'h00000063) && (dbg_pc == last_pc)) begin
                halt_count = halt_count + 1;
            end else begin
                halt_count = 0;
            end

            if ((dbg_instr == 32'h00000063) && (cycle_count > 20)) begin
                halt_marker_count = halt_marker_count + 1;
            end

            if ((dbg_pc == last_pc4) && (cycle_count > 30)) begin
                loop4_count = loop4_count + 1;
            end else begin
                loop4_count = 0;
            end

            last_pc4 = last_pc3;
            last_pc3 = last_pc2;
            last_pc2 = last_pc;
            last_pc = dbg_pc;

            if ((halt_count >= 8) || (halt_marker_count >= 8) || (loop4_count >= 12)) begin
                $display("[TB][PASS] Halt loop detected at cycle=%0d pc=0x%0h instr=0x%08h", cycle_count, dbg_pc, dbg_instr);
                $display("[TB][STATE] dbg_alu=0x%08h dbg_rd=0x%0h", dbg_alu, dbg_rd);
                $finish;
            end
        end

        $display("[TB][TIMEOUT] cycle=%0d pc=0x%0h instr=0x%08h", cycle_count, dbg_pc, dbg_instr);
        $display("[TB][STATE] dbg_alu=0x%08h dbg_rd=0x%0h", dbg_alu, dbg_rd);
        $finish;
    end
endmodule
