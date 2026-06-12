# ascon_intermediate.py
"""
ASCON-Hash256 reference simulator that exposes internal states at each step.
Used to compute intermediate values for Correlation Power Analysis (CPA).
Matches the hardware configuration: ROUNDS_A = 12, ROUNDS_B = 8.
"""

import numpy as np

MASK64 = (1 << 64) - 1

def rotr(x, n):
    return ((x >> n) | ((x & ((1 << n) - 1)) << (64 - n))) & MASK64

def bytes_to_int(b):
    return sum(x << (8 * i) for i, x in enumerate(b)) & MASK64

def int_to_bytes(x, n):
    return bytes([(x >> (8 * i)) & 0xff for i in range(n)])

def bytes_to_state(b):
    return [bytes_to_int(b[8 * i:8 * (i + 1)]) for i in range(5)]

def ascon_round(S, r):
    """Perform one single round of ASCON permutation with round index r (0..11)"""
    S = list(S)
    
    # 1. Round constant addition
    S[2] ^= (0xf0 - r * 0x10 + r)
    
    # 2. Affine layer 1
    S[0] ^= S[4]
    S[4] ^= S[3]
    S[2] ^= S[1]
    
    # Save S after affine 1 for Chi-layer inputs
    S_aff1 = S[:]
    
    # 3. Chi layer (non-linear)
    T0 = ((~S[0]) & MASK64) & S[1]
    T1 = ((~S[1]) & MASK64) & S[2]
    T2 = ((~S[2]) & MASK64) & S[3]
    T3 = ((~S[3]) & MASK64) & S[4]
    T4 = ((~S[4]) & MASK64) & S[0]
    
    S[0] ^= T1
    S[1] ^= T2
    S[2] ^= T3
    S[3] ^= T4
    S[4] ^= T0
    
    # Save S after Chi layer
    S_chi = S[:]
    
    # 4. Affine layer 2
    S[1] ^= S[0]
    S[0] ^= S[4]
    S[3] ^= S[2]
    S[2] ^= MASK64
    
    # 5. Linear diffusion layer
    S[0] ^= rotr(S[0], 19) ^ rotr(S[0], 28)
    S[1] ^= rotr(S[1], 61) ^ rotr(S[1], 39)
    S[2] ^= rotr(S[2], 1) ^ rotr(S[2], 6)
    S[3] ^= rotr(S[3], 10) ^ rotr(S[3], 17)
    S[4] ^= rotr(S[4], 7) ^ rotr(S[4], 41)
    
    for i in range(5):
        S[i] &= MASK64
        
    return S, S_aff1, S_chi

def ascon_permutation_trace(S, start_round, rounds):
    """
    Runs permutation and returns:
    - final state
    - list of states after each round
    - list of states after Chi layer of each round
    - list of states after Affine 1 layer of each round
    """
    S = list(S)
    round_states = []
    chi_states = []
    aff1_states = []
    
    for r in range(start_round, start_round + rounds):
        S, S_aff1, S_chi = ascon_round(S, r)
        round_states.append(S)
        chi_states.append(S_chi)
        aff1_states.append(S_aff1)
        
    return S, round_states, chi_states, aff1_states

class AsconIntermediateCalculator:
    def __init__(self, rounds_a=12, rounds_b=12, rate=8):
        self.rounds_a = rounds_a
        self.rounds_b = rounds_b
        self.rate = rate
        
        # IV
        variant = "Ascon-Hash256"
        versions = {"Ascon-Hash256": 2}
        taglen = 256
        iv = bytes([versions[variant], 0, (rounds_a << 4) + rounds_a]) + \
             int_to_bytes(taglen, 2) + \
             bytes([rate, 0, 0])
             
        # Initialization State
        S_init_in = bytes_to_state(iv + b'\x00' * 32)
        # Init runs rounds_a=12 (rounds 0..11)
        self.S_init, _, _, _ = ascon_permutation_trace(S_init_in, 0, rounds_a)
        
    def compute_intermediates(self, message: bytes):
        """
        Computes intermediate values for an 8-byte message.
        Returns a dictionary with all intermediate states.
        """
        assert len(message) == self.rate, f"Message must be exactly {self.rate} bytes"
        
        results = {}
        results['S_init'] = self.S_init[:]
        
        # 1. Absorb Block 0 (the message)
        S_abs0_in = self.S_init[:]
        msg_val = bytes_to_int(message)
        S_abs0_in[0] ^= msg_val
        results['S_abs0_in'] = S_abs0_in[:]
        
        S_pro, round_states_b, chi_states_b, aff1_states_b = ascon_permutation_trace(
        S_abs0_in, 0, self.rounds_b   # start_round = 0
        )
        results['S_pro'] = S_pro[:]
        results['round_states_b'] = round_states_b
        results['chi_states_b'] = chi_states_b
        results['aff1_states_b'] = aff1_states_b
        
        # 2. Absorb Block 1 (Padding: 0x01 followed by rate-1 zeros)
        # Wait! For 8-byte message, the hardware FSM transitions to PAD_MSG directly
        # where it XORs the 1-bit padding directly.
        # This is S_pro[0] ^= 1.
        S_abs1_in = S_pro[:]
        S_abs1_in[0] ^= 1
        results['S_abs1_in'] = S_abs1_in[:]
        
        # Run final permutation (FINAL) -> rounds_a=12 (rounds 0..11)
        S_final, round_states_a, chi_states_a, aff1_states_a = ascon_permutation_trace(
            S_abs1_in, 0, self.rounds_a
        )
        results['S_final'] = S_final[:]
        results['round_states_a'] = round_states_a
        results['chi_states_a'] = chi_states_a
        results['aff1_states_a'] = aff1_states_a
        
        return results

if __name__ == "__main__":
    calc = AsconIntermediateCalculator()
    msg = bytes.fromhex("9d79b1a37f31801c")
    res = calc.compute_intermediates(msg)
    print("S_init x0:", hex(res['S_init'][0]))
    print("S_abs0_in x0:", hex(res['S_abs0_in'][0]))
    print("S_pro x0:", hex(res['S_pro'][0]))
    print("S_final x0:", hex(res['S_final'][0]))
