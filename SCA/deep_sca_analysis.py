#!/usr/bin/env python3
"""
deep_sca_analysis.py
Deep side-channel analysis: uses the full ASCON-Hash256 reference implementation
to iterate over all critical rounds (now including per-layer intermediates),
supports multiple intermediate value models (HW/HD/word-level/byte-level/layer-level),
and performs CPA and SNR analysis with visualizations.

Place this script in the same directory as ascon_intermediate.py.
"""

import os
import sys
import numpy as np
import h5py
import matplotlib.pyplot as plt
import argparse
from tqdm import tqdm
from ascon_intermediate import AsconIntermediateCalculator, int_to_bytes, bytes_to_int

plt.style.use('seaborn-v0_8-whitegrid' if 'seaborn-v0_8-whitegrid' in plt.style.available else 'default')
plt.rcParams.update({'font.size': 11, 'axes.labelsize': 12, 'axes.titlesize': 14,
                     'xtick.labelsize': 10, 'ytick.labelsize': 10, 'figure.titlesize': 16})

# ------------------------------------------------------------
# Utility functions
# ------------------------------------------------------------
HW_LUT = np.array([bin(i).count('1') for i in range(256)], dtype=np.uint8)

def compute_hw(val: int, bits: int = 64) -> int:
    """Hamming weight of integer val, configurable bit width (default 64)."""
    hw = 0
    while val:
        hw += (val & 1)
        val >>= 1
    return hw

def compute_hw_word(val: int) -> int:
    """Hamming weight of a 64-bit word."""
    return compute_hw(val, 64)

def compute_hw_byte(b: int) -> int:
    return HW_LUT[b & 0xFF]

def compute_hd(val_a: int, val_b: int) -> int:
    """Hamming distance between two integers."""
    return compute_hw_word(val_a ^ val_b)

def pearson_correlation(X, Y):
    """Pearson correlation: X 1D array, Y 2D array (column-wise)."""
    X_mean = np.mean(X)
    Y_mean = np.mean(Y, axis=0)
    X_c = X - X_mean
    Y_c = Y - Y_mean
    numerator = np.dot(X_c, Y_c)
    denom = np.sqrt(np.sum(X_c**2) * np.sum(Y_c**2, axis=0))
    corr = np.zeros_like(numerator)
    mask = denom > 1e-12
    corr[mask] = numerator[mask] / denom[mask]
    return corr

def snr_analysis(leakages, groups):
    """
    Signal-to-noise ratio analysis: partitions traces by group label,
    returns SNR time series.
    groups: 1D array of group labels (0..K-1) for each trace.
    """
    unique_groups = np.unique(groups)
    means = []
    vars_ = []
    for g in unique_groups:
        mask = (groups == g)
        if np.sum(mask) < 2:
            continue
        group_traces = leakages[mask]
        means.append(np.mean(group_traces, axis=0))
        vars_.append(np.var(group_traces, axis=0, ddof=1))
    if len(means) == 0:
        return np.zeros(leakages.shape[1])
    means = np.array(means)
    vars_ = np.array(vars_)
    var_of_means = np.var(means, axis=0)
    mean_of_vars = np.mean(vars_, axis=0)
    snr = np.zeros_like(var_of_means)
    mask_denom = mean_of_vars > 1e-12
    snr[mask_denom] = var_of_means[mask_denom] / mean_of_vars[mask_denom]
    snr[~mask_denom & (var_of_means > 0)] = 100.0   # perfect SNR when noise is zero
    return snr

# ------------------------------------------------------------
# Intermediate value extractor
# ------------------------------------------------------------
class IntermediateExtractor:
    """
    Extracts various intermediate values from each message using the ASCON reference.
    Now includes per-layer models (constant addition, Affine1, Chi, Affine2, Linear).
    """
    def __init__(self):
        self.calc = AsconIntermediateCalculator()

    def extract(self, message: bytes, model: str, round_idx: int = 0, word_idx: int = 0, byte_idx: int = 0):
        """
        Returns an integer (8-bit or 64-bit) according to the chosen model, round and index.
        
        Supported models (original):
          - 'msg_byte'       : raw message byte (byte_idx)
          - 'absorb_word'    : absorption state S_abs0_in[word_idx] (full 64-bit word)
          - 'pro_round_state': PRO_MSG state after full round round_idx, word word_idx
          - 'pro_round_chi'  : PRO_MSG Chi output of round round_idx, word word_idx
          - 'pro_round_aff1' : PRO_MSG Affine1 output of round round_idx, word word_idx
          - 'final_round_state': FINAL state after full round round_idx, word word_idx
          - 'final_round_chi'  : FINAL Chi output of round round_idx, word word_idx
          - 'final_round_aff1' : FINAL Affine1 output of round round_idx, word word_idx
          - 'absorb_word_hd'   : Hamming distance of word word_idx between S_init and S_abs0_in
          - 'pro_round_chi_hd' : Hamming distance between consecutive PRO_MSG Chi outputs
          - 'final_round_chi_hd' : Hamming distance between consecutive FINAL Chi outputs
        
        Supported new per-layer models (PRO & FINAL):
          - 'pro_layer_const'  : Constant addition output HW
          - 'pro_layer_aff1'   : Affine1 output HW (same as pro_round_aff1)
          - 'pro_layer_chi'    : Chi output HW (same as pro_round_chi)
          - 'pro_layer_aff2'   : Affine2 output HW
          - 'pro_layer_lin'    : Linear diffusion output HW (same as pro_round_state)
          - 'pro_layer_const_hd' : HD from round input to const output
          - 'pro_layer_aff1_hd'  : HD from const output to Affine1 output
          - 'pro_layer_chi_hd'   : HD from Affine1 output to Chi output
          - 'pro_layer_aff2_hd'  : HD from Chi output to Affine2 output
          - 'pro_layer_lin_hd'   : HD from Affine2 output to linear output
        
        Similarly for 'final_layer_*' (replace pro with final).
        
        Round index: 0..11 for both PRO_MSG and FINAL (12 rounds each).
        """
        res = self.calc.compute_intermediates(message)
        model = model.lower()

        # --- Original models ---
        if model == 'msg_byte':
            return message[byte_idx]
        elif model == 'absorb_word':
            S_abs0 = res['S_abs0_in']
            return S_abs0[word_idx]
        elif model == 'pro_round_state':
            states = res['round_states_b']
            return states[round_idx][word_idx]
        elif model == 'pro_round_chi':
            states = res['chi_states_b']
            return states[round_idx][word_idx]
        elif model == 'pro_round_aff1':
            states = res['aff1_states_b']
            return states[round_idx][word_idx]
        elif model == 'final_round_state':
            states = res['round_states_a']
            return states[round_idx][word_idx]
        elif model == 'final_round_chi':
            states = res['chi_states_a']
            return states[round_idx][word_idx]
        elif model == 'final_round_aff1':
            states = res['aff1_states_a']
            return states[round_idx][word_idx]
        elif model == 'absorb_word_hd':
            S_init = res['S_init']
            S_abs0 = res['S_abs0_in']
            return compute_hd(S_init[word_idx], S_abs0[word_idx])
        elif model == 'pro_round_chi_hd':
            chi_states = res['chi_states_b']
            if round_idx == 0:
                prev_chi = res['S_abs0_in'][word_idx]   # approximate as state before permutation
            else:
                prev_chi = chi_states[round_idx - 1][word_idx]
            curr_chi = chi_states[round_idx][word_idx]
            return compute_hd(prev_chi, curr_chi)
        elif model == 'final_round_chi_hd':
            chi_states = res['chi_states_a']
            if round_idx == 0:
                prev_chi = res['S_abs1_in'][word_idx]
            else:
                prev_chi = chi_states[round_idx - 1][word_idx]
            curr_chi = chi_states[round_idx][word_idx]
            return compute_hd(prev_chi, curr_chi)

        # --- New per-layer models ---
        # Determine stage (pro/final) and pick relevant internal arrays
        if model.startswith('pro_layer'):
            stage = 'b'          # PRO_MSG
            round_states = res['round_states_b']
            chi_states   = res['chi_states_b']
            aff1_states  = res['aff1_states_b']
            S_init_stage = res['S_abs0_in']
            # PRO_MSG uses rounds_b rounds (now 12), but global permutation index depends on implementation.
            # We assume the permutation trace starts at start_round = 0 for simplicity (if rounds_b=12).
            start_rnd    = 0   # The calculator now returns rounds_b=12 starting from 0
            num_rounds   = self.calc.rounds_b   # should be 12
        elif model.startswith('final_layer'):
            stage = 'a'
            round_states = res['round_states_a']
            chi_states   = res['chi_states_a']
            aff1_states  = res['aff1_states_a']
            S_init_stage = res['S_abs1_in']
            start_rnd    = 0
            num_rounds   = self.calc.rounds_a   # 12
        else:
            raise ValueError(f"Unknown model: {model}")

        if round_idx < 0 or round_idx >= num_rounds:
            raise ValueError(f"Round index {round_idx} out of range (0..{num_rounds-1}) for model {model}")

        # Round input S_in
        if round_idx == 0:
            S_in = S_init_stage[:]
        else:
            S_in = round_states[round_idx - 1][:]

        # Round constant (global index: start_rnd + round_idx)
        global_r = start_rnd + round_idx
        rc = (0xf0 - global_r * 0x10 + global_r) & ((1<<64)-1)

        # Compute constant addition output
        S_const = S_in[:]
        S_const[2] ^= rc

        # Affine1, Chi outputs (from precomputed arrays)
        S_aff1 = aff1_states[round_idx][:]
        S_chi  = chi_states[round_idx][:]

        # Affine2 output: computed from S_chi
        S_aff2 = S_chi[:]
        S_aff2[1] ^= S_aff2[0]
        S_aff2[0] ^= S_aff2[4]
        S_aff2[3] ^= S_aff2[2]
        S_aff2[2] ^= ((1<<64)-1)   # invert

        # Linear diffusion output (same as round_states)
        S_lin = round_states[round_idx][:]

        # Return depending on the specific layer
        layer = model[model.find('layer_'):]  # e.g. 'layer_const' or 'layer_const_hd'
        if layer == 'layer_const':
            return S_const[word_idx]
        elif layer == 'layer_aff1':
            return S_aff1[word_idx]
        elif layer == 'layer_chi':
            return S_chi[word_idx]
        elif layer == 'layer_aff2':
            return S_aff2[word_idx]
        elif layer == 'layer_lin':
            return S_lin[word_idx]
        elif layer == 'layer_const_hd':
            return compute_hd(S_in[word_idx], S_const[word_idx])
        elif layer == 'layer_aff1_hd':
            return compute_hd(S_const[word_idx], S_aff1[word_idx])
        elif layer == 'layer_chi_hd':
            return compute_hd(S_aff1[word_idx], S_chi[word_idx])
        elif layer == 'layer_aff2_hd':
            return compute_hd(S_chi[word_idx], S_aff2[word_idx])
        elif layer == 'layer_lin_hd':
            return compute_hd(S_aff2[word_idx], S_lin[word_idx])
        else:
            raise ValueError(f"Unknown model: {model}")

    def get_hw(self, val, model, byte_idx=None):
        """
        Computes Hamming weight from the extracted value.
        For byte-level models, returns 8-bit HW; for HD models, returns the value itself;
        otherwise, returns 64-bit HW.
        """
        if 'byte' in model:
            return compute_hw_byte(val)
        elif 'hd' in model:
            return val   # already a Hamming distance
        else:
            return compute_hw_word(val)

# ------------------------------------------------------------
# Analysis runners
# ------------------------------------------------------------
def load_traces(h5_path, feature):
    print(f"Loading dataset '{feature}' from {h5_path}")
    with h5py.File(h5_path, 'r') as f:
        if feature not in f:
            print(f"Error: dataset '{feature}' does not exist in the file.")
            sys.exit(1)
        leakages = f[feature][:]
        messages_hex = f['messages'][:]
        messages = [bytes.fromhex(m.decode('utf-8')) for m in messages_hex]
    return leakages, messages

def run_cpa_for_models(leakages, messages, models_to_run, words, output_dir, selected_rounds=None):
    """
    CPA over all specified models, words and rounds (optionally filtered).
    Generates: per-round correlation traces, heatmaps, and max correlation vs. round plots.
    """
    extractor = IntermediateExtractor()
    num_traces, num_samples = leakages.shape
    results = {}   # key: (model, word, round_idx) -> correlation trace

    print("Starting CPA computation...")
    # Both PRO and FINAL now use 12 rounds
    round_counts = {
        'pro_round_state': 12, 'pro_round_chi': 12, 'pro_round_aff1': 12,
        'final_round_state': 12, 'final_round_chi': 12, 'final_round_aff1': 12,
        'absorb_word': 1, 'msg_byte': 1,
        'absorb_word_hd': 1,
        'pro_round_chi_hd': 12, 'final_round_chi_hd': 12,
        # per-layer models (12 rounds each)
        'pro_layer_const': 12, 'pro_layer_aff1': 12, 'pro_layer_chi': 12,
        'pro_layer_aff2': 12, 'pro_layer_lin': 12,
        'pro_layer_const_hd': 12, 'pro_layer_aff1_hd': 12, 'pro_layer_chi_hd': 12,
        'pro_layer_aff2_hd': 12, 'pro_layer_lin_hd': 12,
        'final_layer_const': 12, 'final_layer_aff1': 12, 'final_layer_chi': 12,
        'final_layer_aff2': 12, 'final_layer_lin': 12,
        'final_layer_const_hd': 12, 'final_layer_aff1_hd': 12, 'final_layer_chi_hd': 12,
        'final_layer_aff2_hd': 12, 'final_layer_lin_hd': 12,
    }
    for model in models_to_run:
        rounds = round_counts.get(model, 0)
        if rounds == 0:
            print(f"Warning: Unknown model '{model}', skipping.")
            continue
        for word in words:
            # Determine which rounds to process for this model
            rounds_to_do = range(rounds)
            if selected_rounds is not None:
                rounds_to_do = [r for r in selected_rounds if r < rounds]
                if not rounds_to_do:
                    print(f"  No matching rounds for {model} (selected rounds: {selected_rounds})")
                    continue

            for r in rounds_to_do:
                hws = np.zeros(num_traces)
                for i, msg in enumerate(tqdm(messages, desc=f"{model} w{word} r{r}", leave=False)):
                    val = extractor.extract(msg, model, round_idx=r, word_idx=word)
                    hws[i] = extractor.get_hw(val, model)
                corr_trace = pearson_correlation(hws, leakages)
                key = (model, word, r)
                results[key] = corr_trace
                print(f"  Model {model}, word {word}, round {r}: max |r| = {np.max(np.abs(corr_trace)):.4f}")

    os.makedirs(output_dir, exist_ok=True)

    # 1) Overlay of correlation traces across rounds (per model, per word)
    for model in models_to_run:
        rounds = round_counts.get(model, 0)
        if rounds == 0:
            continue
        for word in words:
            plt.figure(figsize=(14, 6))
            for r in range(rounds):
                corr = results.get((model, word, r))
                if corr is not None:
                    plt.plot(np.abs(corr), label=f'Round {r}', alpha=0.7)
            plt.title(f'CPA |r| trace: {model}, word x{word}')
            plt.xlabel('Time Sample')
            plt.ylabel('Absolute Correlation |r|')
            plt.legend()
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, f'cpa_{model}_word{word}_all_rounds.png'), dpi=200)
            plt.close()

    # 2) Heatmap: round vs. time (absolute correlation)
    for model in models_to_run:
        rounds = round_counts.get(model, 0)
        if rounds <= 1:
            continue
        for word in words:
            corr_matrix = np.zeros((rounds, num_samples))
            for r in range(rounds):
                corr = results.get((model, word, r))
                if corr is not None:
                    corr_matrix[r, :] = np.abs(corr)
            plt.figure(figsize=(12, 8))
            plt.imshow(corr_matrix, aspect='auto', cmap='plasma', interpolation='nearest')
            plt.colorbar(label='|r|')
            plt.title(f'CPA Heatmap: {model}, word x{word}')
            plt.xlabel('Time Sample')
            plt.ylabel('Round')
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, f'heatmap_{model}_word{word}.png'), dpi=200)
            plt.close()

    # 3) Maximum |r| vs. round
    for model in models_to_run:
        rounds = round_counts.get(model, 0)
        if rounds <= 1:
            continue
        for word in words:
            max_corrs = [np.max(np.abs(results.get((model, word, r), [0]))) for r in range(rounds)]
            plt.figure(figsize=(10, 4))
            plt.plot(range(rounds), max_corrs, marker='o')
            plt.title(f'Max |r| vs Round: {model}, word x{word}')
            plt.xlabel('Round')
            plt.ylabel('Maximum Absolute Correlation')
            plt.grid(True)
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, f'max_corr_{model}_word{word}.png'), dpi=200)
            plt.close()

    return results

def run_snr_for_models(leakages, messages, models_to_run, words, output_dir, selected_rounds=None):
    """SNR analysis, grouping by Hamming weight (0..64 or 0..8)."""
    extractor = IntermediateExtractor()
    num_traces = leakages.shape[0]
    round_counts = {
        'pro_round_state': 12, 'pro_round_chi': 12, 'pro_round_aff1': 12,
        'final_round_state': 12, 'final_round_chi': 12, 'final_round_aff1': 12,
        'absorb_word': 1, 'msg_byte': 1,
        'pro_layer_const': 12, 'pro_layer_aff1': 12, 'pro_layer_chi': 12,
        'pro_layer_aff2': 12, 'pro_layer_lin': 12,
        'pro_layer_const_hd': 12, 'pro_layer_aff1_hd': 12, 'pro_layer_chi_hd': 12,
        'pro_layer_aff2_hd': 12, 'pro_layer_lin_hd': 12,
        'final_layer_const': 12, 'final_layer_aff1': 12, 'final_layer_chi': 12,
        'final_layer_aff2': 12, 'final_layer_lin': 12,
        'final_layer_const_hd': 12, 'final_layer_aff1_hd': 12, 'final_layer_chi_hd': 12,
        'final_layer_aff2_hd': 12, 'final_layer_lin_hd': 12,
    }
    print("Starting SNR computation...")
    for model in models_to_run:
        rounds = round_counts.get(model, 0)
        if rounds == 0:
            continue
        for word in words:
            rounds_to_do = range(rounds)
            if selected_rounds is not None:
                rounds_to_do = [r for r in selected_rounds if r < rounds]
            for r in rounds_to_do:
                hws = np.zeros(num_traces, dtype=np.int32)
                for i, msg in enumerate(tqdm(messages, desc=f"SNR {model} w{word} r{r}", leave=False)):
                    val = extractor.extract(msg, model, round_idx=r, word_idx=word)
                    hws[i] = extractor.get_hw(val, model)
                snr_trace = snr_analysis(leakages, hws)
                plt.figure(figsize=(10, 4))
                plt.plot(snr_trace)
                plt.title(f'SNR: {model}, word x{word}, round {r}')
                plt.xlabel('Time Sample')
                plt.ylabel('SNR')
                plt.tight_layout()
                plt.savefig(os.path.join(output_dir, f'snr_{model}_word{word}_round{r}.png'), dpi=200)
                plt.close()
                print(f"  SNR {model} w{word} r{r}: max SNR = {np.max(snr_trace):.4f}")

def main():
    parser = argparse.ArgumentParser(description="ASCON-Hash256 Deep Side-Channel Analysis")
    parser.add_argument('--trace_file', type=str, default='sca_traces.h5',
                        help='Path to the HDF5 trace file')
    parser.add_argument('--feature', type=str, default='hw_state',
                        help='Name of the leakage feature dataset to analyze')
    parser.add_argument('--models', nargs='+',
                        default=['pro_round_chi', 'final_round_chi', 'absorb_word'],
                        help='Intermediate models to analyze. Choose from original or new per-layer models.')
    parser.add_argument('--words', nargs='+', type=int, default=[0],
                        help='State word indices to analyze (0..4)')
    parser.add_argument('--output_dir', type=str, default='deep_sca_results',
                        help='Directory for output plots')
    parser.add_argument('--run_snr', action='store_true',
                        help='Also run SNR analysis')
    parser.add_argument('--rounds', nargs='+', type=int, default=None,
                        help='Specific round indices to analyze (0-based). If not set, all rounds are processed.')
    args = parser.parse_args()

    # Fallback to existing traces if the specified file is missing
    h5_path = args.trace_file
    if not os.path.exists(h5_path):
        for fallback in ['traces_valid.h5', 'traces_x0.h5']:
            if os.path.exists(fallback):
                h5_path = fallback
                args.feature = 'leakages'
                print(f"Warning: '{args.trace_file}' not found. Falling back to '{fallback}' "
                      f"(feature='leakages').")
                break
        else:
            print("Error: No trace file found.")
            sys.exit(1)

    leakages, messages = load_traces(h5_path, args.feature)
    print(f"Trace shape: {leakages.shape}, number of messages: {len(messages)}")

    run_cpa_for_models(leakages, messages, args.models, args.words, args.output_dir, args.rounds)
    if args.run_snr:
        run_snr_for_models(leakages, messages, args.models, args.words, args.output_dir, args.rounds)

if __name__ == "__main__":
    main()