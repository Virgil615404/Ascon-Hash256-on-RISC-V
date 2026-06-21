#!/usr/bin/env python3
"""
RISC-V RV32I ISA Reference Model
Provides golden-standard simulation for verification purposes.
"""

import sys
from typing import Dict, List, Tuple
from dataclasses import dataclass
from enum import IntEnum

# ============================================================================
# Register Definitions
# ============================================================================

class Register(IntEnum):
    X0 = 0    # Zero
    X1 = 1    # Return Address
    X2 = 2    # Stack Pointer
    X3 = 3    # Global Pointer
    X4 = 4    # Thread Pointer
    X5 = 5    # Temp
    X6 = 6    # Temp
    X7 = 7    # Temp
    X8 = 8    # Saved (Frame Pointer)
    X9 = 9    # Saved
    X10 = 10  # Arg 0 / Return Value
    X11 = 11  # Arg 1 / Return Value
    X12 = 12  # Arg 2
    X13 = 13  # Arg 3
    X14 = 14  # Arg 4
    X15 = 15  # Arg 5
    X16 = 16  # Arg 6
    X17 = 17  # Arg 7
    X18 = 18  # Saved
    X19 = 19  # Saved
    X20 = 20  # Saved
    X21 = 21  # Saved
    X22 = 22  # Saved
    X23 = 23  # Saved
    X24 = 24  # Saved
    X25 = 25  # Saved
    X26 = 26  # Saved
    X27 = 27  # Saved
    X28 = 28  # Saved
    X29 = 29  # Saved
    X30 = 30  # Saved
    X31 = 31  # Saved

# ============================================================================
# Instruction Decoding
# ============================================================================

@dataclass
class Instruction:
    """Decoded RISC-V instruction"""
    opcode: int
    rd: int
    rs1: int
    rs2: int
    imm: int
    instr_type: str  # R, I, S, B, U, J
    mnemonic: str
    raw: int

# ============================================================================
# Reference Model Core
# ============================================================================

class RV32IRefModel:
    """
    RISC-V RV32I Reference Model
    
    Provides instruction-accurate simulation of a RISC-V RV32I core.
    Maintains architectural state and validates against hardware behavior.
    """
    
    def __init__(self, imem_init: Dict[int, int] = None):
        """
        Initialize reference model.
        
        Args:
            imem_init: Dictionary mapping addresses to 32-bit instructions
        """
        # Registers (32 x 32-bit)
        self.regs = [0] * 32
        self.regs[2] = 0  # Default SP matches hardware reset
        
        # Memory (4GB address space, sparse storage)
        self.memory = {}
        if imem_init:
            self.memory.update(imem_init)
        
        # Program counter
        self.pc = 0
        self.next_pc = 0
        
        # Execution state
        self.cycle_count = 0
        self.instruction_count = 0
        self.halt = False
        
        # Execution log for debugging/comparison
        self.exec_log = []
        
    # ========================================================================
    # State Management
    # ========================================================================
    
    def set_register(self, rd: int, value: int) -> None:
        """Set register value (x0 is always 0)"""
        if rd != 0:
            self.regs[rd] = value & 0xFFFFFFFF
    
    def get_register(self, rs: int) -> int:
        """Get register value"""
        return self.regs[rs] & 0xFFFFFFFF
    
    def read_mem(self, addr: int) -> int:
        """Read word from memory"""
        addr_word = addr & ~3
        return self.memory.get(addr_word, 0) & 0xFFFFFFFF
    
    def read_mem_byte(self, addr: int) -> int:
        """Read byte from memory"""
        word = self.read_mem(addr & ~3)
        byte_idx = addr & 3
        return (word >> (byte_idx * 8)) & 0xFF
    
    def read_mem_half(self, addr: int) -> int:
        """Read halfword from memory"""
        word = self.read_mem(addr & ~3)
        half_idx = (addr >> 1) & 1
        return (word >> (half_idx * 16)) & 0xFFFF
    
    def write_mem(self, addr: int, value: int) -> None:
        """Write word to memory"""
        addr_word = addr & ~3
        self.memory[addr_word] = value & 0xFFFFFFFF
    
    def write_mem_byte(self, addr: int, byte_value: int) -> None:
        """Write byte to memory"""
        addr_word = addr & ~3
        byte_idx = addr & 3
        mask = ~(0xFF << (byte_idx * 8))
        current = self.memory.get(addr_word, 0)
        self.memory[addr_word] = (current & mask) | ((byte_value & 0xFF) << (byte_idx * 8))
    
    def write_mem_half(self, addr: int, half_value: int) -> None:
        """Write halfword to memory"""
        addr_word = addr & ~3
        half_idx = (addr >> 1) & 1
        mask = ~(0xFFFF << (half_idx * 16))
        current = self.memory.get(addr_word, 0)
        self.memory[addr_word] = (current & mask) | ((half_value & 0xFFFF) << (half_idx * 16))
    
    # ========================================================================
    # Instruction Decoding
    # ========================================================================
    
    def sign_extend(self, value: int, bits: int) -> int:
        """Sign extend value from 'bits' to 32-bit"""
        if value & (1 << (bits - 1)):
            value |= (-1 << bits)
        return value & 0xFFFFFFFF
    
    def decode_instr(self, raw: int) -> Instruction:
        """Decode 32-bit instruction"""
        opcode = raw & 0x7F
        rd = (raw >> 7) & 0x1F
        rs1 = (raw >> 15) & 0x1F
        rs2 = (raw >> 20) & 0x1F
        funct3 = (raw >> 12) & 0x7
        funct7 = (raw >> 25) & 0x7F
        
        # I-type immediate
        imm_i = self.sign_extend((raw >> 20) & 0xFFF, 12)
        
        # S-type immediate
        imm_s = self.sign_extend(((raw >> 25) << 5) | ((raw >> 7) & 0x1F), 12)
        
        # B-type immediate
        imm_b = self.sign_extend((
            ((raw >> 31) << 12) |
            ((raw >> 7) & 0x1) << 11 |
            ((raw >> 25) & 0x3F) << 5 |
            ((raw >> 8) & 0xF) << 1
        ), 13)
        
        # U-type immediate
        imm_u = (raw & 0xFFFFF000) & 0xFFFFFFFF
        
        # J-type immediate
        imm_j = self.sign_extend((
            ((raw >> 31) << 20) |
            ((raw >> 21) & 0x3FF) << 1 |
            ((raw >> 20) & 0x1) << 11 |
            ((raw >> 12) & 0xFF) << 12
        ), 21)
        
        instr_type = ""
        mnemonic = ""
        imm = 0
        
        # Decode instruction
        if opcode == 0x37:  # LUI
            instr_type = "U"
            mnemonic = "LUI"
            imm = imm_u
        elif opcode == 0x17:  # AUIPC
            instr_type = "U"
            mnemonic = "AUIPC"
            imm = imm_u
        elif opcode == 0x6F:  # JAL
            instr_type = "J"
            mnemonic = "JAL"
            imm = imm_j
        elif opcode == 0x67:  # JALR
            instr_type = "I"
            mnemonic = "JALR"
            imm = imm_i
        elif opcode == 0x63:  # Branch
            instr_type = "B"
            imm = imm_b
            if funct3 == 0: mnemonic = "BEQ"
            elif funct3 == 1: mnemonic = "BNE"
            elif funct3 == 4: mnemonic = "BLT"
            elif funct3 == 5: mnemonic = "BGE"
            elif funct3 == 6: mnemonic = "BLTU"
            elif funct3 == 7: mnemonic = "BGEU"
        elif opcode == 0x03:  # Load
            instr_type = "I"
            imm = imm_i
            if funct3 == 0: mnemonic = "LB"
            elif funct3 == 1: mnemonic = "LH"
            elif funct3 == 2: mnemonic = "LW"
            elif funct3 == 4: mnemonic = "LBU"
            elif funct3 == 5: mnemonic = "LHU"
        elif opcode == 0x23:  # Store
            instr_type = "S"
            imm = imm_s
            if funct3 == 0: mnemonic = "SB"
            elif funct3 == 1: mnemonic = "SH"
            elif funct3 == 2: mnemonic = "SW"
        elif opcode == 0x13:  # OP-IMM
            instr_type = "I"
            imm = imm_i
            if funct3 == 0: mnemonic = "ADDI"
            elif funct3 == 2: mnemonic = "SLTI"
            elif funct3 == 3: mnemonic = "SLTIU"
            elif funct3 == 4: mnemonic = "XORI"
            elif funct3 == 6: mnemonic = "ORI"
            elif funct3 == 7: mnemonic = "ANDI"
            elif funct3 == 1: mnemonic = "SLLI"
            elif funct3 == 5:
                if funct7 == 0: mnemonic = "SRLI"
                else: mnemonic = "SRAI"
        elif opcode == 0x33:  # OP
            instr_type = "R"
            if funct3 == 0:
                if funct7 == 0: mnemonic = "ADD"
                else: mnemonic = "SUB"
            elif funct3 == 1: mnemonic = "SLL"
            elif funct3 == 2: mnemonic = "SLT"
            elif funct3 == 3: mnemonic = "SLTU"
            elif funct3 == 4: mnemonic = "XOR"
            elif funct3 == 5:
                if funct7 == 0: mnemonic = "SRL"
                else: mnemonic = "SRA"
            elif funct3 == 6: mnemonic = "OR"
            elif funct3 == 7: mnemonic = "AND"
        
        return Instruction(opcode, rd, rs1, rs2, imm, instr_type, mnemonic, raw)
    
    # ========================================================================
    # Instruction Execution
    # ========================================================================
    
    def execute_instr(self, instr: Instruction) -> Tuple[int, Dict]:
        """
        Execute instruction and return (next_pc, state_change).
        
        Returns:
            next_pc: Address of next instruction
            state: Dict with 'rd', 'rd_value', 'mem_addr', 'mem_value', etc.
        """
        state = {}
        next_pc = self.pc + 4
        
        mnem = instr.mnemonic
        rs1_val = self.get_register(instr.rs1)
        rs2_val = self.get_register(instr.rs2)
        
        if mnem == "LUI":
            result = instr.imm & 0xFFFFFFFF
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "AUIPC":
            result = (self.pc + instr.imm) & 0xFFFFFFFF
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "JAL":
            self.set_register(instr.rd, next_pc)
            next_pc = (self.pc + instr.imm) & 0xFFFFFFFF
            state['rd'] = instr.rd
            state['value'] = next_pc - 4  # Return address
            state['pc'] = next_pc
        
        elif mnem == "JALR":
            self.set_register(instr.rd, next_pc)
            next_pc = (rs1_val + instr.imm) & ~1
            state['rd'] = instr.rd
            state['value'] = next_pc - 4
            state['pc'] = next_pc
        
        elif mnem in ["BEQ", "BNE", "BLT", "BGE", "BLTU", "BGEU"]:
            taken = False
            if mnem == "BEQ": taken = rs1_val == rs2_val
            elif mnem == "BNE": taken = rs1_val != rs2_val
            elif mnem == "BLT": taken = self.sign_extend(rs1_val, 32) < self.sign_extend(rs2_val, 32)
            elif mnem == "BGE": taken = self.sign_extend(rs1_val, 32) >= self.sign_extend(rs2_val, 32)
            elif mnem == "BLTU": taken = rs1_val < rs2_val
            elif mnem == "BGEU": taken = rs1_val >= rs2_val
            
            if taken:
                next_pc = (self.pc + instr.imm) & 0xFFFFFFFF
            state['taken'] = taken
            state['pc'] = next_pc
        
        elif mnem == "LB":
            addr = rs1_val + instr.imm
            value = self.sign_extend(self.read_mem_byte(addr), 8)
            self.set_register(instr.rd, value)
            state['rd'] = instr.rd
            state['mem_addr'] = addr
            state['value'] = value
        
        elif mnem == "LH":
            addr = rs1_val + instr.imm
            value = self.sign_extend(self.read_mem_half(addr), 16)
            self.set_register(instr.rd, value)
            state['rd'] = instr.rd
            state['mem_addr'] = addr
            state['value'] = value
        
        elif mnem == "LW":
            addr = rs1_val + instr.imm
            value = self.read_mem(addr)
            self.set_register(instr.rd, value)
            state['rd'] = instr.rd
            state['mem_addr'] = addr
            state['value'] = value
        
        elif mnem == "LBU":
            addr = rs1_val + instr.imm
            value = self.read_mem_byte(addr)
            self.set_register(instr.rd, value)
            state['rd'] = instr.rd
            state['mem_addr'] = addr
            state['value'] = value
        
        elif mnem == "LHU":
            addr = rs1_val + instr.imm
            value = self.read_mem_half(addr)
            self.set_register(instr.rd, value)
            state['rd'] = instr.rd
            state['mem_addr'] = addr
            state['value'] = value
        
        elif mnem == "SB":
            addr = rs1_val + instr.imm
            self.write_mem_byte(addr, rs2_val)
            state['mem_addr'] = addr
            state['mem_value'] = rs2_val
            state['mem_size'] = 1
        
        elif mnem == "SH":
            addr = rs1_val + instr.imm
            self.write_mem_half(addr, rs2_val)
            state['mem_addr'] = addr
            state['mem_value'] = rs2_val
            state['mem_size'] = 2
        
        elif mnem == "SW":
            addr = rs1_val + instr.imm
            self.write_mem(addr, rs2_val)
            state['mem_addr'] = addr
            state['mem_value'] = rs2_val
            state['mem_size'] = 4
        
        elif mnem == "ADDI":
            result = (rs1_val + instr.imm) & 0xFFFFFFFF
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "SLTI":
            result = 1 if self.sign_extend(rs1_val, 32) < self.sign_extend(instr.imm, 32) else 0
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "SLTIU":
            result = 1 if rs1_val < (instr.imm & 0xFFFFFFFF) else 0
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "XORI":
            result = rs1_val ^ instr.imm
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "ORI":
            result = rs1_val | instr.imm
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "ANDI":
            result = rs1_val & instr.imm
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "SLLI":
            shamt = instr.imm & 0x1F
            result = (rs1_val << shamt) & 0xFFFFFFFF
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "SRLI":
            shamt = instr.imm & 0x1F
            result = rs1_val >> shamt
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "SRAI":
            shamt = instr.imm & 0x1F
            sign_bit = (rs1_val >> 31) & 1
            if sign_bit:
                result = (rs1_val >> shamt) | ((~0) << (32 - shamt))
            else:
                result = rs1_val >> shamt
            result &= 0xFFFFFFFF
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "ADD":
            result = (rs1_val + rs2_val) & 0xFFFFFFFF
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "SUB":
            result = (rs1_val - rs2_val) & 0xFFFFFFFF
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "SLL":
            shamt = rs2_val & 0x1F
            result = (rs1_val << shamt) & 0xFFFFFFFF
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "SLT":
            result = 1 if self.sign_extend(rs1_val, 32) < self.sign_extend(rs2_val, 32) else 0
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "SLTU":
            result = 1 if rs1_val < rs2_val else 0
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "XOR":
            result = rs1_val ^ rs2_val
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "SRL":
            shamt = rs2_val & 0x1F
            result = rs1_val >> shamt
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "SRA":
            shamt = rs2_val & 0x1F
            sign_bit = (rs1_val >> 31) & 1
            if sign_bit:
                result = (rs1_val >> shamt) | ((~0) << (32 - shamt))
            else:
                result = rs1_val >> shamt
            result &= 0xFFFFFFFF
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "OR":
            result = rs1_val | rs2_val
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        elif mnem == "AND":
            result = rs1_val & rs2_val
            self.set_register(instr.rd, result)
            state['rd'] = instr.rd
            state['value'] = result
        
        return next_pc, state
    
    # ========================================================================
    # Simulation Interface
    # ========================================================================
    
    def step(self) -> Tuple[bool, str]:
        """
        Execute one instruction.
        
        Returns:
            (halt, log_entry): Whether program halted, and execution log
        """
        raw_instr = self.read_mem(self.pc)
        instr = self.decode_instr(raw_instr)
        
        # Detect halt (beq x0, x0, 0)
        if raw_instr == 0x00000063:
            self.halt = True
            return True, f"HALT @ PC={self.pc:08x}"
        
        next_pc, state = self.execute_instr(instr)
        
        # Generate log entry
        log_entry = f"[{self.cycle_count:04d}] PC={self.pc:08x} {instr.mnemonic}"
        if state.get('rd') is not None:
            log_entry += f" x{state['rd']}=0x{state['value']:08x}"
        if state.get('mem_addr') is not None:
            log_entry += f" mem[0x{state['mem_addr']:08x}]"
        
        self.pc = next_pc
        self.cycle_count += 1
        self.instruction_count += 1
        self.exec_log.append(log_entry)
        
        return False, log_entry
    
    def run(self, max_cycles: int = 10000) -> Dict:
        """
        Run simulation until halt or max_cycles.
        
        Returns:
            Summary dict with execution statistics
        """
        while self.cycle_count < max_cycles and not self.halt:
            self.step()
        
        return {
            'cycles': self.cycle_count,
            'instructions': self.instruction_count,
            'halted': self.halt,
            'regs': self.regs.copy(),
            'log_lines': len(self.exec_log)
        }
    
    def get_state_snapshot(self) -> Dict:
        """Get current architectural state"""
        return {
            'pc': self.pc,
            'cycle': self.cycle_count,
            'regs': self.regs.copy(),
            'memory': self.memory.copy()
        }
    
    def compare_with_state(self, other_regs: List[int], other_pc: int) -> List[str]:
        """Compare with external state and return mismatches"""
        mismatches = []
        
        if self.pc != other_pc:
            mismatches.append(f"PC mismatch: ref=0x{self.pc:08x} vs hw=0x{other_pc:08x}")
        
        for i in range(32):
            if self.regs[i] != other_regs[i]:
                mismatches.append(
                    f"x{i} mismatch: ref=0x{self.regs[i]:08x} vs hw=0x{other_regs[i]:08x}"
                )
        
        return mismatches


# ============================================================================
# Main Interface
# ============================================================================

def load_hex_file(filename: str) -> Dict[int, int]:
    """Load hex file and return instruction memory dict"""
    imem = {}
    addr = 0
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                imem[addr] = int(line, 16)
                addr += 4
    return imem


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python isa_reference_model.py <hex_file>")
        sys.exit(1)
    
    # Load program
    imem = load_hex_file(sys.argv[1])
    model = RV32IRefModel(imem)
    
    # Run simulation
    results = model.run()
    
    print(f"\n=== Reference Model Execution Summary ===")
    print(f"Cycles: {results['cycles']}")
    print(f"Instructions: {results['instructions']}")
    print(f"Halted: {results['halted']}")
    print(f"\nFinal Register State:")
    for i in range(0, 32, 8):
        for j in range(8):
            if i + j < 32:
                print(f"  x{i+j:2d} = 0x{results['regs'][i+j]:08x}", end="")
        print()
    
    print(f"\nExecution Log (last 20 lines):")
    for line in model.exec_log[-20:]:
        print(f"  {line}")
