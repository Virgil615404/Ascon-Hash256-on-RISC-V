# Ascon‑Hash256 on RISC‑V: Performance & Simulation‑Based Leakage Assessment

This repository contains all RTL, simulation scripts, and analysis tools for the URECA project evaluating Ascon‑Hash256 on a lightweight RISC‑V SoC with MMIO/DMA integration and a simulation‑based side‑channel leakage framework.

## Repository Structure

- `ARCH/` – RISC‑V SoC and accelerator variants
  - `SoC/`          – Base SoC (no accelerator)
  - `StandaloneCore/` – Standalone Ascon‑Hash256 accelerator
  - `MMIO/`         – SoC + MMIO‑integrated accelerator
  - `DMA/`          – SoC + DMA‑integrated accelerator
- `SCA/`           – Side‑channel analysis framework (VCD → HW/HD → TVLA/CPA/SNR)
- `setupenv/`      – Script to set Vivado environment

## Entry Scripts

- **Standalone accelerator**  
  `ARCH\StandaloneCore\StandaloneCore.sim\run_ascon_core_sweep.ps1`

- **RISC‑V SoC verification**  
  `ARCH\SoC\run_tests_windows.bat`

- **MMIO integration benchmark**  
  `ARCH\MMIO\MMIO.sim\run_ascon_benchmark.ps1`

- **DMA integration benchmark**  
  `ARCH\DMA\DMA.sim\run_dma_simple_bench.ps1`

- **Simulation‑based side‑channel analysis**  
  1. Generate VCD traces: `SCA\ascon.sim\run_sims.bat`  
  2. Extract HDF5 traces: `SCA\sca_extract.py`  
  3. Run TVLA/CPA/SNR: `SCA\sca_analysis.py`

## Notes

- All simulations assume Vivado 2025.1. Run `setupenv\setup_vivado_env.ps1` in PowerShell first.
- VCD traces are from behavioural simulation (not post‑layout).
- MMIO/DMA testbenches require manual payload changes inside their `.sv` files; the standalone core automatically sweeps multiple payload sizes.

## License

MIT (see LICENSE file).  
The Ascon‑Hash256 Verilog core is based on the work of Robert Primas (https://github.com/rprimas/ascon-verilog) released under CC0‑1.0. Modifications are indicated in the source files.

## Citation

If you use this work, please cite the accompanying URECA paper (to be added).