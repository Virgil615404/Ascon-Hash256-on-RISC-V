#!/usr/bin/env python3
"""
Negative Test Generator for RISC-V CPU Pipeline

Generates corner-case and error-condition test programs to verify
robustness and error handling of the pipeline.
"""

import sys
from enum import IntEnum

class NegativeTestType(IntEnum):
    """Categories of negative tests"""
    UNALIGNED_ACCESS = 0
    INVALID_OPCODE = 1
    BOUNDARY_VALUES = 2
    HAZARD_STRESS = 3
    MEMORY_STRESS = 4
    BRANCH_STRESS = 5
    ERROR_INJECTION = 6

# ============================================================================
# RV32I Instruction Encoding
# ============================================================================

def encode_r_type(funct7, rs2, rs1, funct3, rd, opcode):
    """R-type: funct7[31:25] rs2[24:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]"""
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_i_type(imm, rs1, funct3, rd, opcode):
    """I-type: imm[31:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]"""
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_s_type(imm, rs2, rs1, funct3, opcode):
    """S-type: imm[31:25] rs2[24:20] rs1[19:15] funct3[14:12] imm[11:7] opcode[6:0]"""
    imm_hi = (imm >> 5) & 0x7F
    imm_lo = imm & 0x1F
    return (imm_hi << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_lo << 7) | opcode

def encode_b_type(imm, rs2, rs1, funct3, opcode):
    """B-type: imm[31] rs2[24:20] rs1[19:15] funct3 imm[4:1|11] opcode"""
    bit12 = (imm >> 12) & 1
    bit11 = (imm >> 11) & 1
    bits10_5 = (imm >> 5) & 0x3F
    bits4_1 = (imm >> 1) & 0xF
    return (bit12 << 31) | (bits10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (bits4_1 << 8) | (bit11 << 7) | opcode

def encode_u_type(imm, rd, opcode):
    """U-type: imm[31:12] rd[11:7] opcode[6:0]"""
    return ((imm & 0xFFFFF000) << 0) | (rd << 7) | opcode

def encode_j_type(imm, rd, opcode):
    """J-type: imm[20|10:1|11|19:12] rd[11:7] opcode[6:0]"""
    bit20 = (imm >> 20) & 1
    bits19_12 = (imm >> 12) & 0xFF
    bit11 = (imm >> 11) & 1
    bits10_1 = (imm >> 1) & 0x3FF
    return (bit20 << 31) | (bits10_1 << 21) | (bit11 << 20) | (bits19_12 << 12) | (rd << 7) | opcode

# ============================================================================
# Test Program Generators
# ============================================================================

class NegativeTestGenerator:
    """Generate negative test programs"""
    
    def __init__(self):
        self.instructions = []
    
    def add_instr(self, instr: int):
        """Add instruction to program"""
        self.instructions.append(instr & 0xFFFFFFFF)
    
    def add_halt(self):
        """Add halt instruction (beq x0, x0, 0)"""
        self.add_instr(0x00000063)
    
    # ========================================================================
    # Test 1: Unaligned Memory Access Detection
    # ========================================================================
    
    def test_unaligned_lw(self):
        """
        Load from unaligned address tests:
        - Load from address+1 (odd address)
        - Load from address+2 (half-aligned)
        - Load from address+3
        """
        self.instructions = []
        
        # Setup: Put base address in x1 (0x1000_0000)
        self.add_instr(encode_u_type(0x10000000, 1, 0x37))  # lui x1, 0x10000
        
        # Store a known value (0x12345678) to 0(x1)
        self.add_instr(encode_u_type(0x12345000, 2, 0x37))  # lui x2, 0x12345
        self.add_instr(encode_i_type(0x678, 2, 0, 2, 0x13))       # addi x2, x2, 0x678
        self.add_instr(encode_s_type(0, 2, 1, 2, 0x23))            # sw x2, 0(x1)
        
        # Test 1: Load from x1 + 1 (unaligned by 1)
        self.add_instr(encode_i_type(1, 1, 2, 10, 0x03))  # lw x10, 1(x1)
        
        # Test 2: Load from x1 + 2 (unaligned by 2)
        self.add_instr(encode_i_type(2, 1, 2, 11, 0x03))  # lw x11, 2(x1)
        
        # Test 3: Compare results
        # If implementation handles gracefully, results should be zero/predictable
        
        self.add_halt()
        return self.instructions
    
    def test_unaligned_sw(self):
        """Store to unaligned address tests"""
        self.instructions = []
        
        # Setup: Put value in x10
        self.add_instr(encode_i_type(0x123, 0, 0, 10, 0x13))  # addi x10, x0, 0x123
        
        # Setup RAM address 0x10000001 in x3
        self.add_instr(encode_u_type(0x10000000, 3, 0x37))  # lui x3, 0x10000
        self.add_instr(encode_i_type(1, 3, 0, 3, 0x13))     # addi x3, x3, 1
        
        # Test: Store to odd address
        self.add_instr(encode_s_type(0, 10, 3, 2, 0x23))  # sw x10, 0(x3)  [unaligned]
        
        # Verify write
        self.add_instr(encode_i_type(0, 3, 2, 11, 0x03))  # lw x11, 0(x3)
        
        self.add_halt()
        return self.instructions
    
    # ========================================================================
    # Test 2: Boundary Value Testing
    # ========================================================================
    
    def test_boundary_values(self):
        """
        Arithmetic boundary tests:
        - Maximum positive 32-bit integer
        - Maximum negative 32-bit integer
        - Overflow/Underflow detection
        """
        self.instructions = []
        
        # Test 1: 0x7FFFFFFF (max positive)
        self.add_instr(encode_u_type(0x7FFFFFFF, 1, 0x37))  # lui x1, 0x7FFF
        self.add_instr(encode_i_type(0xFFF, 1, 0, 1, 0x13))  # addi x1, x1, -1
        
        # Test 2: Add 1 to max positive (should overflow/wrap)
        self.add_instr(encode_i_type(1, 1, 0, 2, 0x13))  # addi x2, x1, 1
        
        # Test 3: 0x80000000 (min negative)
        self.add_instr(encode_u_type(0x80000000, 3, 0x37))  # lui x3, 0x8000
        
        # Test 4: Subtract from minimum (should overflow)
        self.add_instr(encode_i_type(1, 3, 0, 4, 0x13))  # addi x4, x3, 1
        
        self.add_halt()
        return self.instructions
    
    # ========================================================================
    # Test 3: Pipeline Hazard Stress
    # ========================================================================
    
    def test_rapid_dependencies(self):
        """
        Stress test pipeline hazard detection:
        - Back-to-back dependent instructions
        - Chain of 5+ instructions with dependencies
        """
        self.instructions = []
        
        # Initialize x1 = 10
        self.add_instr(encode_i_type(10, 0, 0, 1, 0x13))  # addi x1, x0, 10
        
        # Chain of dependent instructions
        for i in range(7):
            rd = 2 + i  # x2, x3, x4, ...
            rs1 = 1 + i  # x1, x2, x3, ...
            self.add_instr(encode_i_type(1, rs1, 0, rd, 0x13))  # addi x(rd), x(rs1), 1
        
        # Final result should be x8 = 17
        
        self.add_halt()
        return self.instructions
    
    # ========================================================================
    # Test 4: Memory Stress Test
    # ========================================================================
    
    def test_memory_stress(self):
        """
        Stress test memory subsystem:
        - Rapid read/write cycles
        - Large block transfers
        - Cache conflict patterns
        """
        self.instructions = []
        
        # Setup: Put base address in x1 (0x1000_0000)
        self.add_instr(encode_u_type(0x10000000, 1, 0x37))  # lui x1, 0x10000
        
        # Fill memory with pattern
        for i in range(16):
            # Write pattern 0x12345670 + i
            pattern = 0x12345670 + i
            self.add_instr(encode_u_type(pattern, 10, 0x37))
            self.add_instr(encode_i_type(pattern & 0xFFF, 10, 0, 10, 0x13))
            
            # Store to memory[x1 + i*4]
            self.add_instr(encode_s_type(i*4, 10, 1, 2, 0x23))  # sw x10, i*4(x1)
        
        # Read back and verify
        for i in range(16):
            rd = 11 + i
            self.add_instr(encode_i_type(i*4, 1, 2, rd, 0x03))  # lw x(rd), i*4(x1)
        
        self.add_halt()
        return self.instructions
    
    # ========================================================================
    # Test 5: Branch Stress Test
    # ========================================================================
    
    def test_branch_prediction_stress(self):
        """
        Stress test branch prediction and target calculation:
        - Alternating taken/not-taken patterns
        - Extreme branch offsets
        - Nested branches
        """
        self.instructions = []
        
        # Initialize counter
        self.add_instr(encode_i_type(0, 0, 0, 1, 0x13))  # addi x1, x0, 0
        
        # Loop 10 times with branch
        loop_start = len(self.instructions)
        
        # Increment counter
        self.add_instr(encode_i_type(1, 1, 0, 1, 0x13))  # addi x1, x1, 1
        
        # Branch back if x1 < 10
        # blt x1, x2, loop_start
        # First set x2 = 10
        self.add_instr(encode_i_type(10, 0, 0, 2, 0x13))  # addi x2, x0, 10
        
        # Compute branch offset in bytes
        branch_offset = -((len(self.instructions) - loop_start) * 4)
        self.add_instr(encode_b_type(branch_offset, 2, 1, 4, 0x63))  # blt x1, x2, offset
        
        # Final x1 should be 10
        
        self.add_halt()
        return self.instructions
    
    # ========================================================================
    # Test 6: Shift Boundary Test
    # ========================================================================
    
    def test_shift_boundaries(self):
        """
        Test shift amount boundaries:
        - Shift 0 (no shift)
        - Shift 31 (max shift)
        - Shift 32 and beyond (undefined behavior)
        """
        self.instructions = []
        
        # Initialize x1 = 0x12345678
        self.add_instr(encode_u_type(0x12345, 1, 0x37))  # lui x1, 0x12345
        self.add_instr(encode_i_type(0x678, 1, 0, 1, 0x13))  # addi x1, x1, 0x678
        
        # Test shift by 0
        self.add_instr(encode_i_type(0, 1, 1, 2, 0x13))  # slli x2, x1, 0
        
        # Test shift by 31
        self.add_instr(encode_i_type(31, 1, 1, 3, 0x13))  # slli x3, x1, 31
        
        # Test arithmetic shift right by 31
        self.add_instr(encode_r_type(0x20, 0, 1, 5, 4, 0x33))  # sra x4, x1, x0 (shift by 0)
        self.add_instr(encode_i_type(31 | 0x400, 1, 5, 5, 0x13))  # srai x5, x1, 31
        
        self.add_halt()
        return self.instructions
    
    # ========================================================================
    # Test 7: Register Encoding Edge Cases
    # ========================================================================
    
    def test_register_edge_cases(self):
        """
        Test edge cases in register specification:
        - All registers read/written
        - x0 always returns zero
        - Immediate sign extension edge cases
        """
        self.instructions = []
        
        # Test x0 is hardwired to zero
        self.add_instr(encode_i_type(0x7FF, 0, 0, 1, 0x13))  # addi x1, x0, 0x7FF
        # x1 should be 0x7FF, not 0
        
        # Try to write to x0
        self.add_instr(encode_i_type(100, 0, 0, 0, 0x13))  # addi x0, x0, 100
        # x0 should still be 0
        
        # Test immediate sign extension
        # Negative immediate: -1 = 0xFFF (12-bit)
        self.add_instr(encode_i_type(0xFFF, 0, 0, 2, 0x13))  # addi x2, x0, -1
        # x2 should be 0xFFFFFFFF
        
        # Test immediate sign extension: -2048
        self.add_instr(encode_i_type(0x800, 0, 0, 3, 0x13))  # addi x3, x0, -2048
        # x3 should be 0xFFFFF800
        
        self.add_halt()
        return self.instructions
    
    # ========================================================================
    # Test 8: Byte/Halfword Load/Store Edge Cases
    # ========================================================================
    
    def test_byte_halfword_alignment(self):
        """
        Test byte and halfword operations with various alignments:
        - Load byte from each position in a word
        - Load halfword from aligned positions
        - Sign extension correctness
        """
        self.instructions = []
        
        # Setup test word in memory
        # Use RAM address 0x1000_0000
        self.add_instr(encode_u_type(0x10000000, 1, 0x37))  # lui x1, 0x10000
        
        # Write pattern 0xAABBCCDD
        self.add_instr(encode_u_type(0xAABBD000, 2, 0x37))            # lui x2, 0xAABBD
        self.add_instr(encode_i_type(0xCDD, 2, 0, 2, 0x13))           # addi x2, x2, -803 (0xCDD)
        self.add_instr(encode_s_type(0, 2, 1, 2, 0x23))                # sw x2, 0(x1)
        
        # Load byte 0 (should be 0xDD)
        self.add_instr(encode_i_type(0, 1, 0, 3, 0x03))  # lb x3, 0(x1)
        
        # Load byte 1 (should be 0xCC, sign-extended)
        self.add_instr(encode_i_type(1, 1, 0, 4, 0x03))  # lb x4, 1(x1)
        
        # Load halfword 0 (should be 0xCCDD)
        self.add_instr(encode_i_type(0, 1, 1, 5, 0x03))  # lh x5, 0(x1)
        
        self.add_halt()
        return self.instructions
    
    # ========================================================================
    # Output
    # ========================================================================
    
    def to_hex(self, instructions):
        """Convert instructions to hex format"""
        return '\n'.join(f'{instr:08x}' for instr in instructions)
    
    def to_verilog_init(self, instructions):
        """Convert to Verilog memory initialization"""
        lines = []
        for i, instr in enumerate(instructions):
            lines.append(f"mem[{i*4}] = 32'h{instr:08x};")
        return '\n'.join(lines)


# ============================================================================
# Main Interface
# ============================================================================

def main():
    if len(sys.argv) < 2:
        print("Usage: negative_test_generator.py <test_name> [output_file]")
        print()
        print("Available tests:")
        print("  unaligned_lw        - Unaligned load tests")
        print("  unaligned_sw        - Unaligned store tests")
        print("  boundary_values     - Boundary value arithmetic")
        print("  rapid_dependencies  - Pipeline hazard stress")
        print("  memory_stress       - Memory subsystem stress")
        print("  branch_stress       - Branch prediction stress")
        print("  shift_boundaries    - Shift amount boundaries")
        print("  register_edges      - Register encoding edge cases")
        print("  byte_halfword       - Byte/halfword alignment tests")
        sys.exit(1)
    
    test_name = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else f"{test_name}.hex"
    
    gen = NegativeTestGenerator()
    
    if test_name == "unaligned_lw":
        instrs = gen.test_unaligned_lw()
    elif test_name == "unaligned_sw":
        instrs = gen.test_unaligned_sw()
    elif test_name == "boundary_values":
        instrs = gen.test_boundary_values()
    elif test_name == "rapid_dependencies":
        instrs = gen.test_rapid_dependencies()
    elif test_name == "memory_stress":
        instrs = gen.test_memory_stress()
    elif test_name == "branch_stress":
        instrs = gen.test_branch_prediction_stress()
    elif test_name == "shift_boundaries":
        instrs = gen.test_shift_boundaries()
    elif test_name == "register_edges":
        instrs = gen.test_register_edge_cases()
    elif test_name == "byte_halfword":
        instrs = gen.test_byte_halfword_alignment()
    else:
        print(f"Unknown test: {test_name}")
        sys.exit(1)
    
    # Write output
    hex_output = gen.to_hex(instrs)
    with open(output_file, 'w') as f:
        f.write(hex_output)
    
    print(f"Generated {len(instrs)} instructions")
    print(f"Written to: {output_file}")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
