`include "soc_addr_map.vh"

module soc_native_bus(
    input  logic        clk,
    input  logic        rst_n,

    // CPU native data port
    input  logic        cpu_valid,
    input  logic        cpu_we,
    input  logic [31:0] cpu_addr,
    input  logic [31:0] cpu_wdata,
    output logic [31:0] cpu_rdata,

    // RAM port
    output logic        ram_we,
    output logic [31:0] ram_addr,
    output logic [31:0] ram_wdata,
    input  logic [31:0] ram_rdata,

    // UART MMIO port
    output logic        uart_we,
    output logic        uart_re,
    output logic [31:0] uart_addr,
    output logic [31:0] uart_wdata,
    input  logic [31:0] uart_rdata
);
    logic hit_ram;
    logic hit_uart;

    // Compatibility path: low address space can still hit RAM while software migrates.
    always_comb begin
        hit_ram  = ((cpu_addr >= `SOC_RAM_BASE) && (cpu_addr < (`SOC_RAM_BASE + `SOC_RAM_SIZE))) ||
                   (cpu_addr < `SOC_RAM_SIZE);
        hit_uart = (cpu_addr >= `SOC_UART0_BASE) && (cpu_addr < (`SOC_UART0_BASE + `SOC_UART0_SIZE));

        ram_we    = cpu_valid && cpu_we && hit_ram;
        ram_addr  = cpu_addr - (cpu_addr >= `SOC_RAM_BASE ? `SOC_RAM_BASE : 32'h0000_0000);
        ram_wdata = cpu_wdata;

        uart_we    = cpu_valid && cpu_we && hit_uart;
        uart_re    = cpu_valid && !cpu_we && hit_uart;
        uart_addr  = cpu_addr - `SOC_UART0_BASE;
        uart_wdata = cpu_wdata;

        if (!cpu_valid || cpu_we) begin
            cpu_rdata = 32'h0000_0000;
        end else if (hit_ram) begin
            cpu_rdata = ram_rdata;
        end else if (hit_uart) begin
            cpu_rdata = uart_rdata;
        end else begin
            cpu_rdata = 32'hDEAD_BEEF;
        end
    end
endmodule
