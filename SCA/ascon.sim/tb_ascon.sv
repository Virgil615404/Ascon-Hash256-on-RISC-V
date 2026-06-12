`timescale 1ns/1ps
`include "config.sv"

// ===========================================================================
// tb_ascon.sv  –  Ascon-Hash-256 testbench
//
// Protocol recap (from ascon_core.sv):
//   1. Assert mode=M_HASH256 while FSM is IDLE  → triggers idle_done → INIT
//      On the same cycle that idle_done fires, flag_eoi is latched from
//      bdi_eoi.  So bdi_eoi must already be correct when mode first becomes
//      M_HASH256 while fsm==IDLE.
//      For an EMPTY message  → bdi_eoi=1 on that cycle.
//      For a NON-EMPTY message → bdi_eoi=0 on that cycle.
//
//   2. After INIT (12 permutation rounds) the FSM goes to:
//        PAD_MSG  if flag_eoi==1 (empty msg)
//        ABS_MSG  if flag_eoi==0
//
//   3. ABS_MSG: feed words one at a time.
//        bdi_type  = D_MSG
//        |bdi_valid ≠ 0   (bit mask of valid bytes within the CCW-bit word)
//        bdi_ready is driven by the core (=1 in ABS_MSG)
//        bdi_eot   must be 1 on the last word of a block (W64 words)
//        bdi_eoi   must be 1 on the very last word of the whole message
//
//   4. After all words: FINAL → SQZ_HASH (×4) → IDLE  → done=1
// ===========================================================================

module tb_ascon;

  // ── Signals ──────────────────────────────────────────────────────────────
  logic                   clk;
  logic                   rst;
  logic       [  CCW-1:0] bdi;
  logic       [CCW/8-1:0] bdi_valid;
  logic                   bdi_ready;
  data_e                  bdi_type;
  logic                   bdi_eot;
  logic                   bdi_eoi;
  mode_e                  mode;
  logic       [  CCW-1:0] bdo;
  logic                   bdo_valid;
  logic                   bdo_ready;
  data_e                  bdo_type;
  logic                   bdo_eot;
  logic                   bdo_eoo;
  logic                   done;

  // ── UUT ──────────────────────────────────────────────────────────────────
  ascon_core uut (
    .clk      (clk),
    .rst      (rst),
    .bdi      (bdi),
    .bdi_valid(bdi_valid),
    .bdi_ready(bdi_ready),
    .bdi_type (bdi_type),
    .bdi_eot  (bdi_eot),
    .bdi_eoi  (bdi_eoi),
    .mode     (mode),
    .bdo      (bdo),
    .bdo_valid(bdo_valid),
    .bdo_ready(bdo_ready),
    .bdo_type (bdo_type),
    .bdo_eot  (bdo_eot),
    .bdo_eoo  (bdo_eoo),
    .done     (done)
  );

  // ── Clock ─────────────────────────────────────────────────────────────────
  initial clk = 0;
  always  #5 clk = ~clk;   // 100 MHz

  // ── Hash output capture ───────────────────────────────────────────────────
  // 256 bits = 4×64 bits = 4×W64 CCW-bit words
  localparam int HASH_WORDS = 4 * int'(W64);
  logic [CCW-1:0] hash_words [HASH_WORDS];
  int             hash_word_idx;

  always_ff @(posedge clk) begin
    if (rst) begin
      hash_word_idx <= 0;
    end else if (bdo_valid && bdo_ready) begin
      if (hash_word_idx < HASH_WORDS)
        hash_words[hash_word_idx] <= bdo;
      hash_word_idx <= hash_word_idx + 1;
    end
  end

  // ── Message storage ───────────────────────────────────────────────────────
  integer        msg_len;
  logic [7:0]    msg_bytes [];

  // Word-aligned BDI arrays
  int                       num_words;
  logic [    CCW-1:0]       bdi_word_arr  [];
  logic [  CCW/8-1:0]       bdi_valid_arr [];

  // ── Helper task: build word arrays from msg_bytes ─────────────────────────
  task automatic build_word_arrays();
    int bytes_per_word;
    bytes_per_word = CCW / 8;
    num_words = (msg_len + bytes_per_word - 1) / bytes_per_word;
    bdi_word_arr  = new[num_words];
    bdi_valid_arr = new[num_words];
    for (int w = 0; w < num_words; w++) begin
      logic [CCW-1:0]   wv;
      logic [CCW/8-1:0] vv;
      wv = '0; vv = '0;
      for (int b = 0; b < bytes_per_word; b++) begin
        int bidx;
        bidx = w * bytes_per_word + b;
        if (bidx < msg_len) begin
          wv[b*8 +: 8] = msg_bytes[bidx];
          vv[b]        = 1'b1;
        end
      end
      bdi_word_arr[w]  = wv;
      bdi_valid_arr[w] = vv;
    end
  endtask

  // ── Main stimulus ─────────────────────────────────────────────────────────
  string  vcd_file;
  integer fh, fstatus;

  initial begin : stimulus
    // ---- default signal values ----
    rst       = 1;
    bdi       = '0;
    bdi_valid = '0;
    bdi_type  = D_INVALID;
    bdi_eot   = 1'b0;
    bdi_eoi   = 1'b0;
    mode      = M_INVALID;
    bdo_ready = 1'b1;   // always accept output
    bdo_eoo   = 1'b0;   // not used in HASH mode

    // ---- VCD dump ----
    if ($value$plusargs("VCD_FILE=%s", vcd_file))
      $dumpfile(vcd_file);
    else
      $dumpfile("dump.vcd");
    $dumpvars(0, tb_ascon);

    // ---- read input_msg.txt ----
    fh = $fopen("input_msg.txt", "r");
    if (fh == 0) begin
      $display("[TB] ERROR: cannot open input_msg.txt");
      $finish;
    end
    fstatus = $fscanf(fh, "%d\n", msg_len);
    if (fstatus != 1) begin
      $display("[TB] ERROR: cannot read msg_len");
      $fclose(fh);
      $finish;
    end
    if (msg_len > 0) begin
      msg_bytes = new[msg_len];
      for (int i = 0; i < msg_len; i++) begin
        fstatus = $fscanf(fh, "%h\n", msg_bytes[i]);
        if (fstatus != 1) begin
          $display("[TB] ERROR: cannot read byte %0d", i);
          $fclose(fh);
          $finish;
        end
      end
    end
    $fclose(fh);
    $display("[TB] msg_len = %0d bytes", msg_len);

    // ---- build word arrays ----
    if (msg_len > 0) begin
      build_word_arrays();
    end else begin
      num_words = 0;
    end

    // ========================================================
    // RESET  (hold for 10 cycles)
    // ========================================================
    repeat (10) @(posedge clk);
    rst <= 1'b0;
    // Keep mode=M_INVALID, bdi_eoi=0 for one cycle so the FSM
    // sees IDLE but mode≠M_HASH256  (idle_done stays 0 here).
    @(posedge clk);

    // ========================================================
    // START:  assert mode=M_HASH256 so idle_done fires.
    // If msg_len==0 we must also have bdi_eoi=1 RIGHT NOW so
    // flag_eoi gets latched as 1 on this same clock edge.
    // ========================================================
    mode    <= M_HASH256;
    bdi_eoi <= (msg_len == 0) ? 1'b1 : 1'b0;
    // (idle_done will fire on the next posedge where fsm==IDLE
    //  and mode==M_HASH256; that is exactly the next cycle
    //  because the FSM is registered)

    // ========================================================
    // FEED MESSAGE (non-empty only)
    // ========================================================
    if (msg_len > 0) begin : feed_msg
      int w;
      int w64_int;
      w = 0;
      w64_int = int'(W64);   // avoid 4-bit modulo issues

      // Wait until ABS_MSG (bdi_ready goes high)
      @(posedge clk);
      while (!bdi_ready) @(posedge clk);

      while (w < num_words) begin
        // Last word of a block: word index within block == W64-1
        // Last word of message: w == num_words-1
        logic is_last_in_block;
        logic is_last_in_msg;
        is_last_in_block = ((w % w64_int) == (w64_int - 1));
        is_last_in_msg   = (w == num_words - 1);

        bdi_type  <= D_MSG;
        bdi       <= bdi_word_arr[w];
        bdi_valid <= bdi_valid_arr[w];
        bdi_eot   <= is_last_in_block | is_last_in_msg;
        bdi_eoi   <= is_last_in_msg;

        @(posedge clk);
        // bdi_ready is 1 whenever fsm==ABS_MSG (always in that state).
        // Advance word only when core accepts it.
        if (bdi_ready)
          w++;
      end

      // ---- deassert data signals ----
      bdi_valid <= '0;
      bdi_eot   <= 1'b0;
      bdi_eoi   <= 1'b0;
      bdi_type  <= D_INVALID;
      bdi       <= '0;
    end

    // ========================================================
    // WAIT FOR done
    // ========================================================
    @(posedge clk);
    while (!done) @(posedge clk);

    // extra cycles so VCD captures trailing state
    repeat (10) @(posedge clk);

    // ---- print hash ----
    $write("[TB] HASH: ");
    for (int w = 0; w < HASH_WORDS; w++) begin
      for (int b = 0; b < CCW/8; b++) begin
        $write("%02h", hash_words[w][b*8 +: 8]);
      end
    end
    $write("\n");
    $display("[TB] Simulation finished successfully.");
    $finish;
  end

  // ── Watchdog ─────────────────────────────────────────────────────────────
  initial begin : watchdog
    #2000000;   // 2 ms  (2 000 000 ns at 1 ns timescale)
    $display("[TB] ERROR: Simulation TIMEOUT after 2 ms");
    $finish;
  end

endmodule
