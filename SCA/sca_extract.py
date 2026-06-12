#!/usr/bin/env python3
"""
sca_extract.py
Extracts multiple side-channel leakage features from 10,000 ASCON VCD simulation traces.
Features extracted:
  - HW of state (symbol '@')
  - HD of state (consecutive changes of symbol '@')
  - HW of output lanes x0_o..x4_o (symbols 'e'..'i')
Uses multiprocessing for high performance.
"""

import os
import sys
import numpy as np
import pandas as pd
import h5py
from pathlib import Path
from multiprocessing import Pool, cpu_count
from tqdm import tqdm

def extract_vcd_features(vcd_path):
    """
    Parses a single VCD file and returns a dict of feature lists.
    """
    prev_state_val = None
    
    traces = {
        'hw_state': [],
        'hd_state': [],
        'hw_x0_o': [],
        'hw_x1_o': [],
        'hw_x2_o': [],
        'hw_x3_o': [],
        'hw_x4_o': []
    }
    
    try:
        with open(vcd_path, 'r') as f:
            for line in f:
                # VCD vector change lines start with 'b' or 'h'
                if not line.startswith(('b', 'h')):
                    continue
                parts = line.split()
                if len(parts) < 2:
                    continue
                val_str, sym = parts[0], parts[1]
                
                # Check if it is one of the target symbols
                if sym not in ('@', 'e', 'f', 'g', 'h', 'i'):
                    continue
                
                if 'x' in val_str or 'z' in val_str:
                    continue
                
                # Parse to integer
                if val_str[0] == 'b':
                    bin_str = val_str[1:].replace('_', '')
                    if not bin_str:
                        continue
                    int_val = int(bin_str, 2)
                elif val_str[0] == 'h':
                    hex_str = val_str[1:].replace('_', '')
                    if not hex_str:
                        continue
                    int_val = int(hex_str, 16)
                else:
                    continue
                
                hw = bin(int_val).count('1')
                
                if sym == '@':
                    traces['hw_state'].append(hw)
                    if prev_state_val is not None:
                        hd = bin(prev_state_val ^ int_val).count('1')
                        traces['hd_state'].append(hd)
                    else:
                        # Keep aligned with first state change
                        traces['hd_state'].append(0)
                    prev_state_val = int_val
                elif sym == 'e':
                    traces['hw_x0_o'].append(hw)
                elif sym == 'f':
                    traces['hw_x1_o'].append(hw)
                elif sym == 'g':
                    traces['hw_x2_o'].append(hw)
                elif sym == 'h':
                    traces['hw_x3_o'].append(hw)
                elif sym == 'i':
                    traces['hw_x4_o'].append(hw)
                    
    except Exception as e:
        print(f"Error parsing {vcd_path}: {e}", file=sys.stderr)
        return None
        
    # Check if empty
    if not traces['hw_state']:
        return None
        
    # Convert lists to numpy arrays
    for k in traces:
        traces[k] = np.array(traces[k], dtype=np.uint8)
        
    return traces

def process_wrapper(args):
    idx, vcd_path = args
    res = extract_vcd_features(vcd_path)
    return idx, res

def main():
    traces_dir = Path("traces")
    labels_file = Path("traces/labels.txt")
    
    if not traces_dir.is_dir():
        # Try parent directory if running inside traces
        traces_dir = Path(".")
        labels_file = Path("../labels.txt")
        if not labels_file.is_file():
            labels_file = Path("labels.txt")
            
    if not traces_dir.is_dir() or not labels_file.is_file():
        print("ERROR: traces/ directory or labels.txt not found.")
        print("Please run this script from the workspace directory containing the 'traces' folder.")
        sys.exit(1)

    print("Reading labels...")
    df = pd.read_csv(labels_file)
    vcd_filenames = df['vcd_filename'].str.strip().values
    messages = df['message_hex'].values
    num_files = len(vcd_filenames)
    
    print(f"Total VCD files to process: {num_files}")
    
    tasks = []
    for idx, fname in enumerate(vcd_filenames):
        vcd_path = traces_dir / fname
        if vcd_path.exists():
            tasks.append((idx, vcd_path))
        else:
            print(f"Warning: {vcd_path} not found, skipping.")

    num_tasks = len(tasks)
    if num_tasks == 0:
        print("ERROR: No valid VCD files found in the specified path.")
        sys.exit(1)

    # Initialize results containers
    extracted_traces = [None] * num_files
    
    num_workers = max(1, cpu_count() - 1)
    print(f"Starting extraction using {num_workers} parallel workers...")
    
    with Pool(processes=num_workers) as pool:
        for idx, res in tqdm(pool.imap_unordered(process_wrapper, tasks), total=num_tasks, desc="Extracting VCDs"):
            if res is not None:
                extracted_traces[idx] = res

    # Filter out skipped or failed files
    valid_indices = [i for i, r in enumerate(extracted_traces) if r is not None]
    num_valid = len(valid_indices)
    print(f"Successfully processed {num_valid} / {num_files} VCD files.")
    
    if num_valid == 0:
        print("ERROR: No valid traces extracted. Exiting.")
        sys.exit(1)

    # Determine max lengths for padding
    keys = ['hw_state', 'hd_state', 'hw_x0_o', 'hw_x1_o', 'hw_x2_o', 'hw_x3_o', 'hw_x4_o']
    max_lens = {k: 0 for k in keys}
    
    for idx in valid_indices:
        tr = extracted_traces[idx]
        for k in keys:
            max_lens[k] = max(max_lens[k], len(tr[k]))
            
    print("Maximum lengths found:")
    for k in keys:
        print(f"  {k}: {max_lens[k]}")

    # Prepare arrays (pad with zeros to match max length)
    aligned_datasets = {k: np.zeros((num_valid, max_lens[k]), dtype=np.uint8) for k in keys}
    valid_messages = []
    
    for i, idx in enumerate(valid_indices):
        tr = extracted_traces[idx]
        valid_messages.append(messages[idx])
        for k in keys:
            length = len(tr[k])
            aligned_datasets[k][i, :length] = tr[k]

    # Save to HDF5
    output_h5 = "sca_traces.h5"
    print(f"Saving aligned datasets to {output_h5}...")
    
    with h5py.File(output_h5, "w") as f:
        # Save messages as S16 (16-char hex strings)
        msg_bytes = np.array(valid_messages, dtype='S16')
        f.create_dataset("messages", data=msg_bytes)
        
        # Save leakage datasets with gzip compression
        for k in keys:
            f.create_dataset(k, data=aligned_datasets[k], compression="gzip", compression_opts=4)
            print(f"  Saved dataset '{k}' with shape {aligned_datasets[k].shape}")
            
        f.attrs["num_traces"] = num_valid
        for k in keys:
            f.attrs[f"max_len_{k}"] = max_lens[k]
            
    print("Extraction completed successfully!")

if __name__ == "__main__":
    main()
