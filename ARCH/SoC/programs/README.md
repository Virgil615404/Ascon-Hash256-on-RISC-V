# Program Hex Test Set

This folder contains RV32I `.hex` images intended to exercise the SoC with I-cache and D-cache enabled.

## Files
- `smoke_nop.hex`: Basic fetch and halt loop smoke test.
- `auipc_basic.hex`: AUIPC / PC-relative upper immediate path.
- `byte_half_store_load.hex`: Byte and halfword store/load sign-extension path.
- `word_load_sign_ext.hex`: Byte/halfword loads from a known 32-bit word pattern.
- `jalr_selftest.hex`: JALR path and link register behavior.
- `jal_flow.hex`: JAL skip/target control-flow behavior.
- `alu_logic.hex`: R-type ALU/logic operations.
- `alu_imm_ext.hex`: Extra OP-IMM coverage such as XORI, SLTI, SLTIU, SRAI.
- `branch_beq_taken.hex`: BEQ taken path.
- `branch_bne_taken.hex`: BNE taken path.
- `mem_rw_basic.hex`: Basic RAM store/load/compare path.
- `dcache_write_hit.hex`: D-cache write-hit update path.
- `dcache_conflict_writeback.hex`: D-cache dirty eviction + write-back path.

## Format
- One 32-bit instruction per line, hex text (no `0x` prefix required).
- PC starts at address 0.
- Programs end with `00000063` (self-loop halt marker).
