`ifndef SOC_ADDR_MAP_VH
`define SOC_ADDR_MAP_VH

// Address map (32-bit physical address)
`define SOC_RAM_BASE   32'h1000_0000
`define SOC_RAM_SIZE   32'h0001_0000  // 64 KB

`define SOC_UART0_BASE 32'h4000_0000
`define SOC_UART0_SIZE 32'h0000_1000  // 4 KB

`define SOC_ASCON_BASE 32'h4000_1000
`define SOC_ASCON_SIZE 32'h0000_1000  // 4 KB

`endif
