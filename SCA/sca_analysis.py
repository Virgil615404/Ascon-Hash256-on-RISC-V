#!/usr/bin/env python3
"""
sca_analysis.py
Performs side-channel analysis on ASCON-Hash256 simulation traces.
Contains four analysis modules:
  - Module A: TVLA (Test Vector Leakage Assessment) using robust partition t-test
  - Module B: CPA (Correlation Power Analysis) with three intermediate models
  - Module C: SNR (Signal-to-Noise Ratio) analysis
  - Module D: Summary Report & Plot Generation

Modifications:
  - Reports the global maximum |r| for each CPA model along with its byte index and time sample.
  - For --feature hw_state, draws CPA curves for Model 2 (Absorption) for all bytes.
  - For --feature hd_state, draws CPA curves for Model 1 (Raw Message) for all bytes.
"""

import os
import sys
import numpy as np
import h5py
import matplotlib.pyplot as plt
import argparse
from tqdm import tqdm
from ascon_intermediate import AsconIntermediateCalculator

# Ensure plots look clean and professional
plt.style.use('seaborn-v0_8-whitegrid' if 'seaborn-v0_8-whitegrid' in plt.style.available else 'default')
plt.rcParams.update({
    'font.size': 11,
    'axes.labelsize': 12,
    'axes.titlesize': 14,
    'xtick.labelsize': 10,
    'ytick.labelsize': 10,
    'figure.titlesize': 16
})

# Color palette definition
COLORS = {
    'primary': '#1f77b4',     # Steel blue
    'secondary': '#aec7e8',   # Light blue
    'accent': '#ff7f0e',      # Orange
    'highlight': '#d62728',   # Red
    'neutral_dark': '#2c3e50',
    'neutral_light': '#f8f9fa',
    'success': '#2ca02c'      # Green
}

# Hamming weight lookup table for fast execution
HW_LUT = np.array([bin(i).count('1') for i in range(256)], dtype=np.uint8)

def int_to_bytes(val: int, length: int, byteorder: str = 'little') -> bytes:
    """Convert an integer to a bytes object of given length."""
    return val.to_bytes(length, byteorder)

def compute_hw_byte(val):
    return HW_LUT[val & 0xff]

def robust_ttest(g0, g1):
    """
    Welch's t-test robust to noiseless simulation traces (handles zero variance).
    """
    n0 = g0.shape[0]
    n1 = g1.shape[0]
    
    mean0 = np.mean(g0, axis=0)
    mean1 = np.mean(g1, axis=0)
    
    var0 = np.var(g0, axis=0, ddof=1)
    var1 = np.var(g1, axis=0, ddof=1)
    
    denom = np.sqrt(var0 / n0 + var1 / n1)
    
    t = np.zeros_like(mean0)
    zero_mask = (denom == 0)
    non_zero_mask = ~zero_mask
    
    # Calculate regular Welch's t-test where variance is non-zero
    t[non_zero_mask] = (mean0[non_zero_mask] - mean1[non_zero_mask]) / denom[non_zero_mask]
    
    # For zero variance, if means are different, it's perfect leakage (t = infinity)
    diff = mean0 - mean1
    t[zero_mask & (diff != 0)] = np.sign(diff[zero_mask & (diff != 0)]) * 100.0
    t[zero_mask & (diff == 0)] = 0.0
    
    return t

def pearson_correlation(X, Y):
    """
    Pearson correlation coefficient between 1D array X and 2D array Y.
    Vectorized over Y columns.
    """
    X_mean = np.mean(X)
    Y_mean = np.mean(Y, axis=0)
    
    X_centered = X - X_mean
    Y_centered = Y - Y_mean
    
    numerator = np.dot(X_centered, Y_centered)
    
    X_var = np.sum(X_centered**2)
    Y_var = np.sum(Y_centered**2, axis=0)
    
    denom = np.sqrt(X_var * Y_var)
    
    corr = np.zeros_like(numerator)
    non_zero = denom > 1e-12
    corr[non_zero] = numerator[non_zero] / denom[non_zero]
    return corr

def load_traces(h5_path, dataset_name):
    print(f"Loading dataset '{dataset_name}' from {h5_path}...")
    with h5py.File(h5_path, 'r') as f:
        if dataset_name not in f:
            print(f"ERROR: Dataset '{dataset_name}' not found in {h5_path}")
            sys.exit(1)
        leakages = f[dataset_name][:]
        messages_hex = f['messages'][:]
        messages = [bytes.fromhex(m.decode('utf-8')) for m in messages_hex]
    return leakages, messages

def run_tvla(leakages, messages, feature_name):
    """
    Module A: TVLA (Test Vector Leakage Assessment) using robust t-test.
    Partitions the 10,000 traces based on message bit values.
    """
    print(f"\n--- Module A: TVLA on '{feature_name}' ---")
    num_traces, num_samples = leakages.shape
    
    # Convert messages to a binary array of shape (N, 64)
    msg_bits = np.zeros((num_traces, 64), dtype=np.uint8)
    for i, msg in enumerate(messages):
        val = int.from_bytes(msg, byteorder='little')
        for bit in range(64):
            msg_bits[i, bit] = (val >> bit) & 1
            
    # Compute t-statistic for all 64 bits over all time samples
    t_matrix = np.zeros((64, num_samples))
    for bit in tqdm(range(64), desc="TVLA per bit"):
        g0 = leakages[msg_bits[:, bit] == 0]
        g1 = leakages[msg_bits[:, bit] == 1]
        t_matrix[bit, :] = robust_ttest(g0, g1)
        
    max_t_per_bit = np.max(np.abs(t_matrix), axis=1)
    print(f"Max absolute t-statistic across all bits: {np.max(max_t_per_bit):.4f}")
    
    # Generate Heatmap Plot
    plt.figure(figsize=(12, 8))
    plt.imshow(np.abs(t_matrix), aspect='auto', cmap='plasma', interpolation='nearest')
    plt.colorbar(label='Absolute t-statistic')
    plt.title(f'TVLA absolute t-statistic Heatmap ({feature_name})')
    plt.xlabel('Time Sample')
    plt.ylabel('Message Bit Index')
    plt.tight_layout()
    plt.savefig(f'tvla_heatmap_{feature_name}.png', dpi=200)
    plt.close()
    
    # Generate Trace Plot for 8 representative bits (bit 0 of each byte)
    plt.figure(figsize=(14, 6))
    for byte in range(8):
        bit_idx = byte * 8
        plt.plot(t_matrix[bit_idx], label=f'Bit {bit_idx} (Byte {byte})', alpha=0.7, linewidth=1.2)
        
    plt.axhline(4.5, color=COLORS['highlight'], linestyle='--', alpha=0.6, label='Threshold |t|=4.5')
    plt.axhline(-4.5, color=COLORS['highlight'], linestyle='--', alpha=0.6)
    plt.title(f'TVLA t-statistic Traces for Representative Bits ({feature_name})')
    plt.xlabel('Time Sample')
    plt.ylabel('t-statistic')
    plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.tight_layout()
    plt.savefig(f'tvla_traces_{feature_name}.png', dpi=200)
    plt.close()
    
    return t_matrix

def run_cpa(leakages, messages, feature_name):
    """
    Module B: CPA (Correlation Power Analysis) with three models.
    Generates additional plots based on the leakage feature:
      - hw_state: all bytes for Model 2 (Absorption)
      - hd_state: all bytes for Model 1 (Raw Message)
    """
    print(f"\n--- Module B: CPA on '{feature_name}' ---")
    num_traces, num_samples = leakages.shape
    
    # Precompute all intermediate values using Ascon reference
    print("Precomputing intermediate values for CPA models...")
    calc = AsconIntermediateCalculator()
    
    # Power models matrices: shape (8, num_traces)
    model1_hw = np.zeros((8, num_traces)) # Raw message byte HW
    model2_hw = np.zeros((8, num_traces)) # Absorption intermediate byte HW
    model3_hw = np.zeros((8, num_traces)) # First-round Chi-layer byte HW
    
    for i, msg in enumerate(tqdm(messages, desc="Simulating ASCON intermediates")):
        res = calc.compute_intermediates(msg)
        
        # Model 1: Message
        for byte_idx in range(8):
            model1_hw[byte_idx, i] = HW_LUT[msg[byte_idx]]
            
        # Model 2: Absorption
        # S_abs0_in is S_init XOR message. Rate block is the first 8 bytes.
        S_abs0_in = res['S_abs0_in']
        # x0 is the 64-bit word S_abs0_in[0]
        x0_bytes = int_to_bytes(S_abs0_in[0], 8)
        for byte_idx in range(8):
            model2_hw[byte_idx, i] = HW_LUT[x0_bytes[byte_idx]]
            
        # Model 3: Chi-layer Output of Round 4 (first round of PRO_MSG)
        # res['chi_states_b'][0] is the state after the first Chi layer of PRO_MSG
        x0_chi = res['chi_states_b'][0][0]
        x0_chi_bytes = int_to_bytes(x0_chi, 8)
        for byte_idx in range(8):
            model3_hw[byte_idx, i] = HW_LUT[x0_chi_bytes[byte_idx]]
            
    # Perform Correlation Analysis
    corr_model1 = np.zeros((8, num_samples))
    corr_model2 = np.zeros((8, num_samples))
    corr_model3 = np.zeros((8, num_samples))
    
    for byte_idx in range(8):
        corr_model1[byte_idx, :] = pearson_correlation(model1_hw[byte_idx, :], leakages)
        corr_model2[byte_idx, :] = pearson_correlation(model2_hw[byte_idx, :], leakages)
        corr_model3[byte_idx, :] = pearson_correlation(model3_hw[byte_idx, :], leakages)
        
    # Plot comparisons for a representative byte (Byte 0)
    plt.figure(figsize=(14, 6))
    plt.plot(np.abs(corr_model1[0, :]), color=COLORS['secondary'], label='Model 1: Raw Msg HW', alpha=0.8)
    plt.plot(np.abs(corr_model2[0, :]), color=COLORS['primary'], label='Model 2: Absorption HW', alpha=0.8)
    plt.plot(np.abs(corr_model3[0, :]), color=COLORS['accent'], label='Model 3: Chi-layer Output HW', alpha=0.8)
    plt.title(f'CPA Correlation Comparison (Byte 0, {feature_name})')
    plt.xlabel('Time Sample')
    plt.ylabel('Absolute Correlation |r|')
    plt.legend(loc='best')
    plt.tight_layout()
    plt.savefig(f'cpa_model_comparison_{feature_name}.png', dpi=200)
    plt.close()
    
    # Plot all bytes for Model 3 (Chi-layer) – always generated
    plt.figure(figsize=(14, 6))
    for byte_idx in range(8):
        plt.plot(np.abs(corr_model3[byte_idx, :]), label=f'Byte {byte_idx}', alpha=0.7)
    plt.title(f'CPA Model 3 (Chi-layer Output) absolute correlation traces ({feature_name})')
    plt.xlabel('Time Sample')
    plt.ylabel('Absolute Correlation |r|')
    plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.tight_layout()
    plt.savefig(f'cpa_model3_all_bytes_{feature_name}.png', dpi=200)
    plt.close()
    
    # Additional feature‑specific plots
    if feature_name == 'hw_state':
        # Model 2 all bytes for HW feature
        plt.figure(figsize=(14, 6))
        for byte_idx in range(8):
            plt.plot(np.abs(corr_model2[byte_idx, :]), label=f'Byte {byte_idx}', alpha=0.7)
        plt.title(f'CPA Model 2 (Absorption) absolute correlation traces ({feature_name})')
        plt.xlabel('Time Sample')
        plt.ylabel('Absolute Correlation |r|')
        plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
        plt.tight_layout()
        plt.savefig(f'cpa_model2_all_bytes_{feature_name}.png', dpi=200)
        plt.close()
        
    if feature_name == 'hd_state':
        # Model 1 all bytes for HD feature
        plt.figure(figsize=(14, 6))
        for byte_idx in range(8):
            plt.plot(np.abs(corr_model1[byte_idx, :]), label=f'Byte {byte_idx}', alpha=0.7)
        plt.title(f'CPA Model 1 (Raw Msg) absolute correlation traces ({feature_name})')
        plt.xlabel('Time Sample')
        plt.ylabel('Absolute Correlation |r|')
        plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
        plt.tight_layout()
        plt.savefig(f'cpa_model1_all_bytes_{feature_name}.png', dpi=200)
        plt.close()
    
    return corr_model1, corr_model2, corr_model3

def run_snr(leakages, messages, feature_name):
    """
    Module C: SNR (Signal-to-Noise Ratio) analysis.
    Groups traces by the Hamming weight of each message byte.
    """
    print(f"\n--- Module C: SNR Analysis on '{feature_name}' ---")
    num_traces, num_samples = leakages.shape
    
    snr_traces = np.zeros((8, num_samples))
    
    for byte_idx in range(8):
        # Determine HW class (0..8) for each trace
        hws = np.array([HW_LUT[msg[byte_idx]] for msg in messages])
        
        # Calculate means and variances per HW class
        means = []
        vars_val = []
        
        for hw_class in range(9):
            group = leakages[hws == hw_class]
            if len(group) > 1:
                means.append(np.mean(group, axis=0))
                vars_val.append(np.var(group, axis=0, ddof=1))
                
        means = np.array(means)   # shape (K, T)
        vars_val = np.array(vars_val) # shape (K, T)
        
        # SNR = Var(Means) / Mean(Vars)
        var_of_means = np.var(means, axis=0)
        mean_of_vars = np.mean(vars_val, axis=0)
        
        # Avoid zero division
        denom_mask = mean_of_vars > 1e-12
        snr = np.zeros_like(var_of_means)
        snr[denom_mask] = var_of_means[denom_mask] / mean_of_vars[denom_mask]
        # For zero variance, if there is data-dependent variance of means, SNR is very high
        snr[~denom_mask & (var_of_means > 0)] = 100.0
        
        snr_traces[byte_idx, :] = snr
        
    # Plot SNR traces
    plt.figure(figsize=(14, 6))
    for byte_idx in range(8):
        plt.plot(snr_traces[byte_idx, :], label=f'Byte {byte_idx}', alpha=0.7)
    plt.title(f'SNR Traces per Message Byte ({feature_name})')
    plt.xlabel('Time Sample')
    plt.ylabel('SNR')
    plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.tight_layout()
    plt.savefig(f'snr_traces_{feature_name}.png', dpi=200)
    plt.close()
    
    return snr_traces

def generate_report(feature_name, tvla_matrix, corr_m1, corr_m2, corr_m3, snr_traces):
    """
    Module D: Summary Report.
    Now reports the global maximum absolute correlation for each CPA model
    together with the byte index and time sample where it occurs.
    """
    print(f"\n--- Module D: Summary Report for '{feature_name}' ---")
    print("=" * 80)
    print(f"Leakage Feature: {feature_name}")
    print("-" * 80)
    
    # TVLA summary
    max_t = np.max(np.abs(tvla_matrix))
    max_t_idx = np.unravel_index(np.argmax(np.abs(tvla_matrix)), tvla_matrix.shape)
    print(f"TVLA Assessment:")
    print(f"  Max Absolute t-statistic: {max_t:.4f} (at Bit {max_t_idx[0]}, Time Sample {max_t_idx[1]})")
    if max_t > 4.5:
        print("  Status: SIGNIFICANT LEAKAGE DETECTED (t > 4.5)")
    else:
        print("  Status: No significant leakage detected")
        
    print("\nCPA Assessment (Global max absolute correlation |r| per model):")
    # Model 1
    m1_max = np.max(np.abs(corr_m1))
    m1_idx = np.unravel_index(np.argmax(np.abs(corr_m1)), corr_m1.shape)
    print(f"  Model 1 (Raw Msg): Max |r| = {m1_max:.4f} at Byte {m1_idx[0]}, Time Sample {m1_idx[1]}")
    # Model 2
    m2_max = np.max(np.abs(corr_m2))
    m2_idx = np.unravel_index(np.argmax(np.abs(corr_m2)), corr_m2.shape)
    print(f"  Model 2 (Absorption): Max |r| = {m2_max:.4f} at Byte {m2_idx[0]}, Time Sample {m2_idx[1]}")
    # Model 3
    m3_max = np.max(np.abs(corr_m3))
    m3_idx = np.unravel_index(np.argmax(np.abs(corr_m3)), corr_m3.shape)
    print(f"  Model 3 (Chi-layer): Max |r| = {m3_max:.4f} at Byte {m3_idx[0]}, Time Sample {m3_idx[1]}")
    
    # Per‑byte breakdown (existing detailed view)
    print("\nCPA Per‑Byte Max |r|:")
    for byte_idx in range(8):
        m1_byte_max = np.max(np.abs(corr_m1[byte_idx, :]))
        m2_byte_max = np.max(np.abs(corr_m2[byte_idx, :]))
        m3_byte_max = np.max(np.abs(corr_m3[byte_idx, :]))
        print(f"  Byte {byte_idx}: Model 1 = {m1_byte_max:.4f} | Model 2 = {m2_byte_max:.4f} | Model 3 = {m3_byte_max:.4f}")
        
    print("\nSNR Assessment:")
    for byte_idx in range(8):
        snr_max = np.max(snr_traces[byte_idx, :])
        snr_max_sample = np.argmax(snr_traces[byte_idx, :])
        print(f"  Byte {byte_idx}: Max SNR = {snr_max:.4f} (at Time Sample {snr_max_sample})")
    print("=" * 80)

def main():
    parser = argparse.ArgumentParser(description="ASCON-Hash256 Side-Channel Analysis Suite")
    parser.add_argument('--trace_file', type=str, default='sca_traces.h5',
                        help='Path to HDF5 trace file (default: sca_traces.h5)')
    parser.add_argument('--feature', type=str, default='hw_state',
                        choices=['hw_state', 'hd_state', 'hw_x0_o', 'hw_x1_o', 'hw_x2_o', 'hw_x3_o', 'hw_x4_o'],
                        help='Leakage feature dataset to analyze (default: hw_state)')
    args = parser.parse_args()
    
    # Fallback to existing traces if needed
    h5_path = args.trace_file
    if not os.path.exists(h5_path):
        if os.path.exists("traces_valid.h5"):
            h5_path = "traces_valid.h5"
            args.feature = "leakages"
            print(f"Warning: '{args.trace_file}' not found. Falling back to 'traces_valid.h5' with feature 'leakages'.")
        elif os.path.exists("traces_x0.h5"):
            h5_path = "traces_x0.h5"
            args.feature = "leakages"
            print(f"Warning: '{args.trace_file}' not found. Falling back to 'traces_x0.h5' with feature 'leakages'.")
        else:
            print(f"ERROR: Trace file '{args.trace_file}' not found and no fallback HDF5 file exists.")
            sys.exit(1)
            
    # Load traces and messages
    leakages, messages = load_traces(h5_path, args.feature)
    print(f"Traces shape: {leakages.shape}")
    print(f"Number of messages: {len(messages)}")
    
    # Module A: TVLA
    tvla_matrix = run_tvla(leakages, messages, args.feature)
    
    # Module B: CPA
    corr_m1, corr_m2, corr_m3 = run_cpa(leakages, messages, args.feature)
    
    # Module C: SNR
    snr_traces = run_snr(leakages, messages, args.feature)
    
    # Module D: Summary Report
    generate_report(args.feature, tvla_matrix, corr_m1, corr_m2, corr_m3, snr_traces)

if __name__ == "__main__":
    main()