import os
import sys
import subprocess
import random
import shutil
import time

# Configuration
NUM_FIXED = 0      # 不再使用固定消息
NUM_RANDOM = 10  # 4000条随机消息

# Setup paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WORKSPACE_DIR = os.path.dirname(SCRIPT_DIR)
TRACES_DIR = os.path.join(WORKSPACE_DIR, "traces")
LABELS_FILE = os.path.join(TRACES_DIR, "labels.txt")
INPUT_MSG_FILE = os.path.join(SCRIPT_DIR, "input_msg.txt")

def find_vivado_bin():
    """Locate Vivado bin directory and return its absolute path, or None."""
    xvlog_path = shutil.which("xvlog")
    if xvlog_path:
        return os.path.dirname(xvlog_path)
    
    candidate_bases = [
        r"C:\Xilinx\2025.1",
        r"C:\Xilinx\Vivado",
        r"D:\Xilinx\2025.1",
        r"D:\Xilinx\Vivado"
    ]
    
    for base_dir in candidate_bases:
        if not os.path.exists(base_dir):
            continue
        
        # Pattern: base_dir\bin directly
        direct_bin = os.path.join(base_dir, "bin")
        if os.path.exists(direct_bin) and (os.path.exists(os.path.join(direct_bin, "xvlog.exe")) or 
                                           os.path.exists(os.path.join(direct_bin, "xvlog.bat"))):
            return direct_bin
        
        # Pattern: base_dir\<version>\bin
        try:
            subdirs = [d for d in os.listdir(base_dir) if os.path.isdir(os.path.join(base_dir, d))]
            for d in sorted(subdirs, reverse=True):
                bin_path = os.path.join(base_dir, d, "bin")
                if os.path.exists(bin_path) and (os.path.exists(os.path.join(bin_path, "xvlog.exe")) or
                                                 os.path.exists(os.path.join(bin_path, "xvlog.bat"))):
                    return bin_path
        except OSError:
            continue
    
    return None

def write_input_msg(msg_bytes):
    with open(INPUT_MSG_FILE, "w") as f:
        f.write(f"{len(msg_bytes)}\n")
        for b in msg_bytes:
            f.write(f"{b:02x}\n")

def run_command(cmd_list, cwd, description):
    """Run a command without shell=True to handle paths with spaces robustly."""
    quoted_cmd_list = [f'"{x}"' if ' ' in x else x for x in cmd_list]
    print(f"Running: {' '.join(quoted_cmd_list)}")
    try:
        subprocess.run(cmd_list, cwd=cwd, check=True, shell=False)
        print(f"[INFO] {description} successful.")
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] {description} failed with exit code {e.returncode}")
        sys.exit(1)

def generate_unique_random_messages(count):
    """Generate a list of unique random messages (fixed length 8 bytes)."""
    messages = []
    seen_hex = set()
    total_generated = 0
    while len(messages) < count:
        length = 8   # 固定为8字节
        if hasattr(random, "randbytes"):
            msg_bytes = random.randbytes(length)
        else:
            msg_bytes = bytes(random.getrandbits(8) for _ in range(length))
        msg_hex = msg_bytes.hex()
        if msg_hex not in seen_hex:
            seen_hex.add(msg_hex)
            messages.append(msg_bytes)
        total_generated += 1
        if total_generated % 1000 == 0:
            print(f"  Generating messages... {len(messages)}/{count} unique generated (total attempts: {total_generated})")
    print(f"Generated {count} unique messages after {total_generated} total attempts.")
    return messages

def main():
    print("="*60)
    print(" Ascon-Hash Trace Simulation Batch Runner (TVLA)")
    print("="*60)

    # --- Clean previous run data (全新运行) ---
    if os.path.exists(LABELS_FILE):
        print(f"[WARNING] Removing old labels file: {LABELS_FILE}")
        os.remove(LABELS_FILE)
    if os.path.exists(TRACES_DIR):
        for f in os.listdir(TRACES_DIR):
            if f.startswith("trace_") and f.endswith(".vcd"):
                file_path = os.path.join(TRACES_DIR, f)
                print(f"[WARNING] Removing old VCD file: {file_path}")
                os.remove(file_path)
    os.makedirs(TRACES_DIR, exist_ok=True)

    vivado_bin = find_vivado_bin()
    if not vivado_bin:
        print("[ERROR] Could not locate Vivado bin directory. Please ensure Vivado is installed.")
        sys.exit(1)
    
    print(f"[INFO] Using Vivado tools from: {vivado_bin}")
    
    # Build full executable paths
    xvlog_exe = os.path.join(vivado_bin, "xvlog")
    xelab_exe = os.path.join(vivado_bin, "xelab")
    xsim_exe = os.path.join(vivado_bin, "xsim")
    
    if sys.platform.startswith("win"):
        if os.path.exists(xvlog_exe + ".bat"):
            xvlog_exe += ".bat"
        if os.path.exists(xelab_exe + ".bat"):
            xelab_exe += ".bat"
        if os.path.exists(xsim_exe + ".bat"):
            xsim_exe += ".bat"
            
    for exe_path in (xvlog_exe, xelab_exe, xsim_exe):
        if not os.path.exists(exe_path):
            print(f"[ERROR] Missing Vivado tool: {exe_path}")
            sys.exit(1)

    # Step 1: Compile
    print("\n[STEP 1] Compiling source files using xvlog...")
    compile_cmd = [
        xvlog_exe, "-sv",
        "-i", os.path.join(WORKSPACE_DIR, "ascon.srcs"),
        os.path.join(WORKSPACE_DIR, "ascon.srcs", "ascon_core.sv"),
        os.path.join(SCRIPT_DIR, "tb_ascon.sv")
    ]
    run_command(compile_cmd, SCRIPT_DIR, "Compilation")

    # Step 2: Elaborate
    print("\n[STEP 2] Elaborating design using xelab...")
    elaborate_cmd = [
        xelab_exe, "-debug", "typical",
        "-top", "tb_ascon",
        "-snapshot", "tb_ascon_snapshot"
    ]
    run_command(elaborate_cmd, SCRIPT_DIR, "Elaboration")

    # Step 3: Generate all unique random messages first
    print(f"\n[STEP 3] Generating {NUM_RANDOM} unique random messages...")
    random.seed(42)  # Keep reproducibility (optional, comment out for true randomness)
    all_messages = generate_unique_random_messages(NUM_RANDOM)

    # Step 4: Run simulations
    print("\n[STEP 4] Running batch simulations...")
    with open(LABELS_FILE, "w") as f_labels:
        f_labels.write("vcd_filename,message_hex\n")
        total_runs = len(all_messages)
        
        for idx, msg_bytes in enumerate(all_messages):
            msg_hex = msg_bytes.hex()
            vcd_filename = f"trace_{idx}.vcd"
            vcd_path = os.path.join(TRACES_DIR, vcd_filename)
            vcd_path_sv = vcd_path.replace("\\", "/")
            
            # 如果之前崩溃产生了不完整的 VCD 文件，先删除
            if os.path.exists(vcd_path):
                try:
                    os.remove(vcd_path)
                except:
                    pass

            # 重试参数
            max_retries = 3
            retry_delay = 0.5  # 秒
            success = False
            
            for attempt in range(1, max_retries + 1):
                # 打印进度（每100条或第一次重试时显示）
                if idx % 100 == 0 or attempt > 1:
                    print(f"--- Run {idx + 1}/{total_runs} [RANDOM] (attempt {attempt}/{max_retries}) ---")
                    print(f"  Message Length: {len(msg_bytes)} bytes")
                    print(f"  Message (hex):  {msg_hex}")
                    print(f"  VCD File Path:  {vcd_path}")
                
                # 写入当前消息
                write_input_msg(msg_bytes)
                
                # 使用列表形式调用，避免 shell 注入，同时 close_fds=True 防止句柄泄漏
                sim_cmd_str = f'"{xsim_exe}" tb_ascon_snapshot -R -testplusarg "VCD_FILE={vcd_path_sv}"'
                
                try:
                    result = subprocess.run(sim_cmd_str, cwd=SCRIPT_DIR, check=False,
                                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                            text=True, shell=True)
                    
                    # 输出仿真中的关键信息（HASH 或 finished）
                    for line in result.stdout.splitlines():
                        if line.startswith("HASH:") or "Simulation finished" in line:
                            if idx % 100 == 0 or idx == total_runs - 1 or attempt > 1:
                                print(f"  {line}")
                    
                    # 检查返回码
                    if result.returncode == 0:
                        success = True
                        break  # 仿真成功，退出重试循环
                    else:
                        # 错误处理：记录错误信息，然后重试
                        print(f"  [WARNING] Run {idx+1} failed with exit code {result.returncode}")
                        if result.stderr:
                            print(f"  stderr: {result.stderr[:200]}")  # 只打印前200字符
                        # 如果 VCD 已部分生成，删除它以便重试时全新生成
                        if os.path.exists(vcd_path):
                            try:
                                os.remove(vcd_path)
                            except:
                                pass
                        if attempt < max_retries:
                            print(f"  Retrying in {retry_delay}s...")
                            time.sleep(retry_delay)
                        else:
                            print(f"  [ERROR] Run {idx+1} failed after {max_retries} attempts. Exiting.")
                            sys.exit(1)
                            
                except Exception as e:
                    print(f"  [ERROR] Exception during run {idx+1}: {e}")
                    if attempt < max_retries:
                        print(f"  Retrying in {retry_delay}s...")
                        time.sleep(retry_delay)
                    else:
                        print(f"  [ERROR] Exiting after {max_retries} exceptions.")
                        sys.exit(1)
            
            if not success:
                # 理论上不会到这里，但保留安全退出
                sys.exit(1)
            
            # 仿真成功，写入标签（只写一次！）
            f_labels.write(f"{vcd_filename},{msg_hex}\n")
            if (idx + 1) % 100 == 0:
                f_labels.flush()
            
            # 每次仿真后短暂休息，释放系统资源
            time.sleep(0.1)

    print("\n" + "="*60)
    print(" Simulation batch completed successfully!")
    print(f" Traces directory: {TRACES_DIR}")
    print(f" Metadata logs:    {LABELS_FILE}")
    print("="*60)

if __name__ == "__main__":
    main()