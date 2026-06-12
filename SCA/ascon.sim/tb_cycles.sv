`timescale 1ns/1ps
`include "config.sv"

module tb_cycles;
  logic clk = 0, rst = 1;
  logic [CCW-1:0] bdi = '0;
  logic [CCW/8-1:0] bdi_valid = '0;
  logic bdi_ready;
  data_e bdi_type = D_INVALID;
  logic bdi_eot = 0, bdi_eoi = 0;
  mode_e mode = M_INVALID;
  logic [CCW-1:0] bdo;
  logic bdo_valid, bdo_ready = 1;
  data_e bdo_type;
  logic bdo_eot, bdo_eoo;
  logic done;

  ascon_core uut (.*);

  // 100 MHz 时钟
  always #5 clk = ~clk;

  // ── 精确周期测量 ──
  int cycle_total = 0;
  int cycle_start = 0;
  logic done_printed = 0;

  always_ff @(posedge clk) begin
    if (rst) begin
      cycle_total <= 0;
      cycle_start <= 0;
      done_printed <= 0;
    end else begin
      cycle_total <= cycle_total + 1;               // 自由计数器
      // 记录命令生效时刻（mode 变 M_HASH256 的当拍）
      if (mode == M_HASH256 && cycle_start == 0)
        cycle_start <= cycle_total;
      // done 上升沿输出周期数并结束
      if (done && !done_printed && cycle_start != 0) begin
        $display("[TB] Hash complete. Cycles = %0d", cycle_total - cycle_start);
        done_printed <= 1;
        $finish;
      end
    end
  end

  // ── 测试激励 ──
  initial begin
    // 释放复位
    repeat(10) @(posedge clk);
    rst = 0;
    @(posedge clk);                 // 等一拍，确保 FSM 进入 IDLE

    // 发起哈希 (消息非空，所以 bdi_eoi=0)
    mode    <= M_HASH256;
    bdi_eoi <= 1'b0;
    @(posedge clk);                 // FSM 进入 INIT

    // 等待进入 ABS_MSG（bdi_ready 拉高）
    while (!bdi_ready) @(posedge clk);

    // ── 发送 8 字节消息 (默认 CCW=32，需要 2 个字) ──
    // 消息内容: 0x00 0x01 0x02 0x03 0x04 0x05 0x06 0x07 (小端序)
    bdi_type <= D_MSG;
    // Word 0
    bdi       <= 32'h03020100;
    bdi_valid <= 4'b1111;
    bdi_eot   <= 1'b0;
    bdi_eoi   <= 1'b0;
    @(posedge clk);
    // Word 1 (块尾 + 消息结束)
    bdi       <= 32'h07060504;
    bdi_eot   <= 1'b1;
    bdi_eoi   <= 1'b1;
    @(posedge clk);

    // 释放总线
    bdi       <= '0;
    bdi_valid <= '0;
    bdi_eot   <= '0;
    bdi_eoi   <= '0;
    bdi_type  <= D_INVALID;

    // 等待 done（由 always 块处理打印与结束）
    wait (done_printed);
  end

  // ── 看门狗 ──
  initial begin
    #2_000_000;
    $display("[TB] TIMEOUT");
    $finish;
  end
endmodule