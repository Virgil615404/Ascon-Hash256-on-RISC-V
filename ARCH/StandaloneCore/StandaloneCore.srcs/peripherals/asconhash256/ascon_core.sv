`ifndef INCL_ASCON_CORE
`define INCL_ASCON_CORE

`include "config.sv"
`include "functions.sv"
`include "asconp.sv"

module ascon_core (
		input  logic                   clk,
		input  logic                   rst,
		input  logic       [  CCW-1:0] bdi,
		input  logic       [CCW/8-1:0] bdi_valid,
		output logic                   bdi_ready,
		input  data_e                  bdi_type,
		input  logic                   bdi_eot,
		input  logic                   bdi_eoi,
		input  mode_e                  mode,
		output logic       [  CCW-1:0] bdo,
		output logic                   bdo_valid,
		input  logic                   bdo_ready,
		output data_e                  bdo_type,
		output logic                   bdo_eot,
		input  logic                   bdo_eoo,
		output logic                   done
);

	logic [LANES-1:0][W64-1:0][CCW-1:0] state;
	logic [      3:0]                   round_cnt;
	logic [      3:0]                   word_cnt;
	logic [      1:0]                   hash_cnt;
	logic flag_msg_pad, flag_eoi;
	mode_e mode_r;

	typedef enum logic [3:0] {
		INVALID  = 'd0,
		IDLE     = 'd1,
		INIT     = 'd2,
		ABS_MSG  = 'd3,
		PAD_MSG  = 'd4,
		PRO_MSG  = 'd5,
		FINAL    = 'd6,
		SQZ_HASH = 'd7
	} fsms_t;
	fsms_t fsm;
	fsms_t fsm_nx;

	logic last_abs_blk;
	logic add_msg_pad;
	logic abs_msg;

	assign last_abs_blk = (abs_msg && (word_cnt == (W64 - 1)));
	assign add_msg_pad = (fsm == PAD_MSG) || (abs_msg && (bdi_valid != '1));

	logic [3:0] state_idx, lane_idx, word_idx;
	logic [CCW-1:0] state_nx, state_slice, bdi_pad;

	assign word_idx = (CCW == 64) ? 'd0 : state_idx % 2;
	assign lane_idx = (CCW == 64) ? state_idx : state_idx / 2;
	assign state_slice = state[int'(lane_idx)][int'(word_idx)];

	logic [LANES-1:0][W64-1:0][CCW-1:0] asconp_o;

	asconp asconp_i (
		.round_cnt(round_cnt),
		.x0_i(state[0]),
		.x1_i(state[1]),
		.x2_i(state[2]),
		.x3_i(state[3]),
		.x4_i(state[4]),
		.x0_o(asconp_o[0]),
		.x1_o(asconp_o[1]),
		.x2_o(asconp_o[2]),
		.x3_o(asconp_o[3]),
		.x4_o(asconp_o[4])
	);

	logic idle_done, init, init_done;
	logic abs_msg_part, abs_msg_done, pro_msg, pro_msg_done;
	logic fin, fin_done;
	logic sqz_hash, sqz_hash_done1, sqz_hash_done2;

	assign idle_done    = (fsm == IDLE) && (mode == M_HASH256);
	assign init         = (fsm == INIT);
	assign init_done    = init && (round_cnt == UROL);
	assign abs_msg_part = (fsm == ABS_MSG) && (bdi_type == D_MSG) && (|bdi_valid) && bdi_ready;
	assign abs_msg      = abs_msg_part;
	assign abs_msg_done = abs_msg && (last_abs_blk || bdi_eot);
	assign pro_msg      = (fsm == PRO_MSG);
	assign pro_msg_done = (round_cnt == UROL) && pro_msg;
	assign fin         = (fsm == FINAL);
	assign fin_done    = (round_cnt == UROL) && fin;
	assign sqz_hash       = (fsm == SQZ_HASH) && bdo_valid && bdo_ready;
	assign sqz_hash_done1 = (word_cnt == (W64 - 1)) && sqz_hash;
	assign sqz_hash_done2 = ((hash_cnt == 'd3) && sqz_hash_done1) || (sqz_hash && bdo_eoo);

	always_comb begin
		state_nx  = 'd0;
		state_idx = 'd0;
		bdi_ready = 'd0;
		bdo       = 'd0;
		bdo_valid = 'd0;
		bdo_type  = D_INVALID;
		bdo_eot   = 'd0;
		bdi_pad   = 'd0;
		unique case (fsm)
			ABS_MSG: begin
				state_idx = word_cnt;
				bdi_pad = pad(bdi, bdi_valid);
				state_nx = state_slice ^ bdi_pad;
				bdi_ready = 'd1;
				bdo = 'd0;
				bdo_valid = 'd0;
			end
			PAD_MSG: begin
				state_idx = word_cnt;
			end
			SQZ_HASH: begin
				state_idx = word_cnt;
				bdo       = state_slice;
				bdo_valid = 'd1;
				bdo_type  = D_HASH;
				bdo_eot   = (hash_cnt == 'd3) && (word_cnt == (W64 - 1));
			end
			default: ;
		endcase
	end

	always_comb begin
		fsm_nx = fsm;
		if (idle_done) begin
			fsm_nx = INIT;
		end
		if (init_done) begin
			fsm_nx = flag_eoi ? PAD_MSG : ABS_MSG;
		end
		if (abs_msg_done) begin
			if (bdi_valid != '1) begin
				fsm_nx = FINAL;
			end else begin
				if (word_cnt != (W64 - 1)) fsm_nx = PAD_MSG;
				else fsm_nx = PRO_MSG;
			end
		end
		if (fsm == PAD_MSG) begin
			fsm_nx = FINAL;
		end
		if (pro_msg_done) begin
			if (flag_eoi == 0) begin
				fsm_nx = ABS_MSG;
			end else if (flag_msg_pad == 0) begin
				fsm_nx = PAD_MSG;
			end
		end
		if (fin_done) begin
			fsm_nx = SQZ_HASH;
		end
		if (sqz_hash_done1) fsm_nx = FINAL;
		if (sqz_hash_done2) fsm_nx = IDLE;
	end

	always_ff @(posedge clk) begin
		if (rst) begin
			fsm <= IDLE;
		end else begin
			fsm <= fsm_nx;
		end
	end

	always_ff @(posedge clk) begin
		if (rst) begin
			state <= '0;
		end else begin
			if (abs_msg) begin
				state[int'(lane_idx)][int'(word_idx)] <= state_nx;
			end
			if (fsm == PAD_MSG) begin
				state[int'(lane_idx)][int'(word_idx)] <= state_slice ^ 'd1;
			end
			if (idle_done && (mode == M_HASH256)) begin
				state <= '0;
				state[0] <= IV_HASH[0+:64];
			end
			if (init || pro_msg || fin) begin
				state <= asconp_o;
			end
		end
	end

	always_ff @(posedge clk) begin
		if (rst) begin
			word_cnt  <= 'd0;
			hash_cnt  <= 'd0;
			round_cnt <= 'd0;
		end else begin
			if (abs_msg || sqz_hash) begin
				word_cnt <= word_cnt + 'd1;
			end
			if (abs_msg_done) begin
				if (fsm_nx == PAD_MSG) begin
					word_cnt <= word_cnt + 'd1;
				end else begin
					word_cnt <= 'd0;
				end
			end
			if (fsm == PAD_MSG) word_cnt <= 'd0;
			if (sqz_hash_done1) word_cnt <= 'd0;
			if (sqz_hash_done1) hash_cnt <= hash_cnt + 'd1;
			if (abs_msg_done && bdi_eoi) hash_cnt <= 'd0;
			unique case (fsm_nx)
				INIT:    round_cnt <= ROUNDS_A;
				PRO_MSG: round_cnt <= ROUNDS_B;
				FINAL:   round_cnt <= ROUNDS_A;
				default:;
			endcase
			if (init || pro_msg || fin) round_cnt <= round_cnt - UROL;
		end
	end

	always_ff @(posedge clk) begin
		if (rst) begin
			done         <= 'd0;
			flag_eoi     <= 'd0;
			flag_msg_pad <= 'd0;
			mode_r       <= M_INVALID;
		end else begin
			if (idle_done) begin
				flag_eoi     <= bdi_eoi;
				flag_msg_pad <= 'd0;
				done         <= 'd0;
				mode_r       <= mode;
			end
			if (abs_msg_done && bdi_eoi) flag_eoi <= 'd1;
			if (add_msg_pad) flag_msg_pad <= 'd1;
			if ((fsm != IDLE) && (fsm_nx == IDLE)) done <= 'd1;
		end
	end

endmodule

`endif