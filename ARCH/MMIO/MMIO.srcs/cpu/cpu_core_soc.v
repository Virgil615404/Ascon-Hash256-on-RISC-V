module cpu_core_soc(
    input clk,
    input rst_n,

    // Native instruction bus
    output        imem_valid,
    output [9:0]  imem_addr,
    input         imem_ready,
    input  [31:0] imem_rdata,

    // Native data bus (no wait-state in current milestone)
    output        dmem_valid,
    output        dmem_we,
    output [2:0]  dmem_size,
    output [31:0] dmem_addr,
    output [31:0] dmem_wdata,
    input         dmem_ready,
    input  [31:0] dmem_rdata,

    // Debug outputs
    output [31:0] instruct,
    output [9:0]  address,
    output [31:0] ALU_result,
    output [4:0]  rd_address
);

    // IF stage
    wire [9:0] PC;
    wire [31:0] instr_if;

    // IF/ID
    wire [31:0] instr_id;
    wire [9:0] PC_id;

    // ID stage
    wire branch_id, memread_id, memwrite_id, ALUsrc_id, regwrite_id, jal_id, jalr_id;
    wire [1:0] memtoreg_id, ALUop_id;
    wire [31:0] read_data1_id, read_data2_id, imm_id;

    // ID/EX
    wire regwrite_ex, memread_ex, memwrite_ex, ALUsrc_ex, branch_ex, jal_ex, jalr_ex;
    wire [1:0] memtoreg_ex, ALUop_ex;
    wire [31:0] read_data1_ex, read_data2_ex, imm_ex, instr_ex;
    wire [4:0] rs1_ex, rs2_ex, rd_ex;
    wire [9:0] PC_ex;

    // EX stage
    wire [3:0] alu_ctrl;
    wire [31:0] alu_src1, alu_src2, write_data_ex;
    wire [31:0] alu_result_raw_ex;
    wire [31:0] alu_result_ex;
    wire alu_zero_ex;
    wire [9:0] branch_target_ex;
    wire branch_taken_ex;

    // EX/MEM
    wire regwrite_mem, memread_mem, memwrite_mem, branch_mem, jal_mem;
    wire [1:0] memtoreg_mem;
    wire [31:0] alu_result_mem, write_data_mem, instr_mem;
    wire [4:0] rd_mem;
    wire [9:0] PC_mem;
    wire branch_taken_mem;
    wire [9:0] branch_target_mem;

    // MEM stage
    wire [31:0] mem_data_mem;

    // MEM/WB
    wire regwrite_wb;
    wire [1:0] memtoreg_wb;
    wire jal_wb;
    wire [31:0] mem_data_wb, alu_result_wb, instr_wb;
    wire [4:0] rd_wb;
    wire [9:0] PC_wb;

    // WB stage
    wire [31:0] write_data_wb;
    wire [2:0]  load_funct3_wb;

    // Forwarding
    wire [1:0] forwardA, forwardB;

    // Hazard
    wire hazard_stall;
    wire if_stall;
    wire mem_stall;
    wire stall;
    wire flush_id;

    // IF
    PC_reg u_PC_reg (
        .clk          (clk),
        .rst_n        (rst_n),
        .branch_target(branch_target_ex),
        .branch_taken (branch_taken_ex),
        .stall        (stall),
        .PCout        (PC)
    );
    assign address = PC;

    assign imem_valid = 1'b1;
    assign imem_addr  = PC;
    assign instr_if   = imem_rdata;
    assign instruct = instr_if;

    IF_ID u_if_id (
        .clk      (clk),
        .rst_n    (rst_n),
        .flush    (flush_id),
        .stall    (stall),
        .instr_in (instr_if),
        .PC_in    (PC),
        .instr_out(instr_id),
        .PC_out   (PC_id)
    );

    // ID
    register u_reg (
        .clk            (clk),
        .rst_n          (rst_n),
        .regwrite       (regwrite_wb),
        .write_register (rd_wb),
        .write_data     (write_data_wb),
        .read_register1 (instr_id[19:15]),
        .read_data1     (read_data1_id),
        .read_register2 (instr_id[24:20]),
        .read_data2     (read_data2_id)
    );

    control u_control (
        .instruction(instr_id[6:0]),
        .branch     (branch_id),
        .memread    (memread_id),
        .memtoreg   (memtoreg_id),
        .ALUop      (ALUop_id),
        .memwrite   (memwrite_id),
        .ALUsrc     (ALUsrc_id),
        .regwrite   (regwrite_id),
        .jal        (jal_id),
        .jalr       (jalr_id)
    );

    immgen u_immgen (
        .instruct (instr_id),
        .immediate(imm_id)
    );

    hazard_detection u_hazard (
        .ID_rs1     (instr_id[19:15]),
        .ID_rs2     (instr_id[24:20]),
        .EX_rd      (rd_ex),
        .EX_memread (memread_ex),
        .stall      (hazard_stall)
    );

    assign if_stall = !imem_ready;
    assign mem_stall = dmem_valid && !dmem_ready;
    assign stall = hazard_stall || if_stall || mem_stall;

    assign flush_id = branch_taken_ex;

    ID_EX u_id_ex (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush          (branch_taken_ex),
        .stall          (stall),
        .regwrite_in    (regwrite_id),
        .memtoreg_in    (memtoreg_id),
        .memread_in     (memread_id),
        .memwrite_in    (memwrite_id),
        .ALUsrc_in      (ALUsrc_id),
        .ALUop_in       (ALUop_id),
        .branch_in      (branch_id),
        .jal_in         (jal_id),
        .jalr_in        (jalr_id),
        .read_data1_in  (read_data1_id),
        .read_data2_in  (read_data2_id),
        .imm_in         (imm_id),
        .rs1_in         (instr_id[19:15]),
        .rs2_in         (instr_id[24:20]),
        .rd_in          (instr_id[11:7]),
        .PC_in          (PC_id),
        .instr_in       (instr_id),
        .regwrite_out   (regwrite_ex),
        .memtoreg_out   (memtoreg_ex),
        .memread_out    (memread_ex),
        .memwrite_out   (memwrite_ex),
        .ALUsrc_out     (ALUsrc_ex),
        .ALUop_out      (ALUop_ex),
        .branch_out     (branch_ex),
        .jal_out        (jal_ex),
        .jalr_out       (jalr_ex),
        .read_data1_out (read_data1_ex),
        .read_data2_out (read_data2_ex),
        .imm_out        (imm_ex),
        .rs1_out        (rs1_ex),
        .rs2_out        (rs2_ex),
        .rd_out         (rd_ex),
        .PC_out         (PC_ex),
        .instr_out      (instr_ex)
    );

    // EX
    ALUcontrol u_aluctl (
        .ALUop          (ALUop_ex),
        .instruction    (instr_ex),
        .control_signal (alu_ctrl)
    );

    forwarding_unit u_fwd (
        .EX_rs1      (rs1_ex),
        .EX_rs2      (rs2_ex),
        .MEM_rd      (rd_mem),
        .WB_rd       (rd_wb),
        .MEM_regwrite(regwrite_mem),
        .WB_regwrite (regwrite_wb),
        .forwardA    (forwardA),
        .forwardB    (forwardB)
    );

    assign alu_src1 = (forwardA == 2'b10) ? alu_result_mem :
                      (forwardA == 2'b01) ? write_data_wb :
                      read_data1_ex;

    wire [31:0] alu_src2_pre = (forwardB == 2'b10) ? alu_result_mem :
                               (forwardB == 2'b01) ? write_data_wb :
                               read_data2_ex;
    assign alu_src2 = ALUsrc_ex ? imm_ex : alu_src2_pre;

    assign write_data_ex = (forwardB == 2'b10) ? alu_result_mem :
                           (forwardB == 2'b01) ? write_data_wb :
                           read_data2_ex;

    ALU u_alu (
        .control_signal(alu_ctrl),
        .read_data1    (alu_src1),
        .read_data2    (alu_src2),
        .immediate     (imm_ex),
        .ALU_src       (1'b0),
        .ALU_result    (alu_result_raw_ex),
        .ALU_zero      (alu_zero_ex)
    );

    wire is_u_type_ex = (instr_ex[6:0] == 7'b0110111) || (instr_ex[6:0] == 7'b0010111);
    wire is_auipc_ex = (instr_ex[6:0] == 7'b0010111);
    wire [31:0] u_type_imm_ex = {instr_ex[31:12], 12'b0};
    wire [31:0] u_type_result_ex = is_auipc_ex ? ({22'b0, PC_ex} + u_type_imm_ex) : u_type_imm_ex;

    assign alu_result_ex = is_u_type_ex ? u_type_result_ex : alu_result_raw_ex;

    wire [31:0] jalr_target_full = alu_src1 + imm_ex;
    assign branch_target_ex = jalr_ex ? {jalr_target_full[9:1], 1'b0} : (PC_ex - 10'd4 + imm_ex[9:0]);
    assign branch_taken_ex = jalr_ex | (branch_ex & alu_zero_ex);

    EX_MEM u_ex_mem (
        .clk               (clk),
        .rst_n             (rst_n),
        .flush             (1'b0),
        .stall             (mem_stall),
        .regwrite_in       (regwrite_ex),
        .memtoreg_in       (memtoreg_ex),
        .memread_in        (memread_ex),
        .memwrite_in       (memwrite_ex),
        .branch_in         (branch_ex),
        .jal_in            (jal_ex),
        .ALU_result_in     (alu_result_ex),
        .write_data_in     (write_data_ex),
        .rd_in             (rd_ex),
        .PC_in             (PC_ex),
        .instr_in          (instr_ex),
        .branch_taken_in   (branch_taken_ex),
        .branch_target_in  (branch_target_ex),
        .regwrite_out      (regwrite_mem),
        .memtoreg_out      (memtoreg_mem),
        .memread_out       (memread_mem),
        .memwrite_out      (memwrite_mem),
        .branch_out        (branch_mem),
        .jal_out           (jal_mem),
        .ALU_result_out    (alu_result_mem),
        .write_data_out    (write_data_mem),
        .rd_out            (rd_mem),
        .PC_out            (PC_mem),
        .instr_out         (instr_mem),
        .branch_taken_out  (branch_taken_mem),
        .branch_target_out (branch_target_mem)
    );

    // MEM now routed to external native bus
    assign dmem_valid = memread_mem | memwrite_mem;
    assign dmem_we    = memwrite_mem;
    assign dmem_size  = instr_mem[14:12];
    assign dmem_addr  = alu_result_mem;
    assign dmem_wdata = write_data_mem;
    assign mem_data_mem = dmem_rdata;

    MEM_WB u_mem_wb (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush          (1'b0),
        .stall          (mem_stall),
        .regwrite_in    (regwrite_mem),
        .memtoreg_in    (memtoreg_mem),
        .jal_in         (jal_mem),
        .mem_data_in    (mem_data_mem),
        .alu_result_in  (alu_result_mem),
        .rd_in          (rd_mem),
        .PC_in          (PC_mem),
        .instr_in       (instr_mem),
        .regwrite_out   (regwrite_wb),
        .memtoreg_out   (memtoreg_wb),
        .jal_out        (jal_wb),
        .mem_data_out   (mem_data_wb),
        .alu_result_out (alu_result_wb),
        .rd_out         (rd_wb),
        .PC_out         (PC_wb),
        .instr_out      (instr_wb)
    );

    // WB
    wire is_auipc_wb = (instr_wb[6:0] == 7'b0010111);
    wire [31:0] u_type_imm_wb = {instr_wb[31:12], 12'b0};
    assign load_funct3_wb = instr_wb[14:12];

    wire [1:0] load_byte_sel_wb = alu_result_wb[1:0];
    wire [31:0] load_word_wb = mem_data_wb;
    wire [7:0] load_byte_wb = (load_byte_sel_wb == 2'b00) ? load_word_wb[7:0] :
                              (load_byte_sel_wb == 2'b01) ? load_word_wb[15:8] :
                              (load_byte_sel_wb == 2'b10) ? load_word_wb[23:16] :
                                                            load_word_wb[31:24];
    wire [15:0] load_half_wb = alu_result_wb[1] ? load_word_wb[31:16] : load_word_wb[15:0];
    wire [31:0] load_data_wb = (load_funct3_wb == 3'b000) ? {{24{load_byte_wb[7]}}, load_byte_wb} :
                               (load_funct3_wb == 3'b100) ? {24'b0, load_byte_wb} :
                               (load_funct3_wb == 3'b001) ? {{16{load_half_wb[15]}}, load_half_wb} :
                               (load_funct3_wb == 3'b101) ? {16'b0, load_half_wb} :
                                                            load_word_wb;

    assign write_data_wb = (jal_wb) ? {22'b0, PC_wb + 10'd4} :
                           (memtoreg_wb == 2'b01) ? load_data_wb :
                           (memtoreg_wb == 2'b11) ? (is_auipc_wb ? ({22'b0, PC_wb} + u_type_imm_wb) : u_type_imm_wb) :
                           alu_result_wb;

    assign ALU_result = alu_result_ex;
    assign rd_address = rd_wb;

endmodule
