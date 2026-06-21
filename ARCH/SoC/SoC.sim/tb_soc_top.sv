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
        .IMEM_HEX_FILE("programs/_current.hex")
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

            // Convention: a self-looping branch or jump in EX stage indicates program end.
            if (u_top.u_cpu.branch_taken_ex && (u_top.u_cpu.branch_target_ex == u_top.u_cpu.PC_ex)) begin
                halt_count = halt_count + 1;
            end

            if (halt_count >= 5) begin
                $display("[TB][PASS] Halt loop detected at cycle=%0d pc=0x%0h instr=0x%08h", cycle_count, u_top.u_cpu.PC_ex, u_top.u_cpu.instr_ex);
                $display("[TB][STATE] dbg_alu=0x%08h dbg_rd=0x%0h", dbg_alu, dbg_rd);
                $display("[PC] pc=0x%0h", u_top.u_cpu.PC_ex);
                for (int i = 0; i < 32; i = i + 1) begin
                    $display("[REG] x%0d=0x%0h", i, u_top.u_cpu.u_reg.register[i]);
                end
                $finish;
            end
        end

        $display("[TB][TIMEOUT] cycle=%0d pc=0x%0h instr=0x%08h", cycle_count, u_top.u_cpu.PC_ex, u_top.u_cpu.instr_ex);
        $display("[TB][STATE] dbg_alu=0x%08h dbg_rd=0x%0h", dbg_alu, dbg_rd);
        $display("[PC] pc=0x%0h", u_top.u_cpu.PC_ex);
        for (int i = 0; i < 32; i = i + 1) begin
            $display("[REG] x%0d=0x%0h", i, u_top.u_cpu.u_reg.register[i]);
        end
        $finish;
    end
endmodule
