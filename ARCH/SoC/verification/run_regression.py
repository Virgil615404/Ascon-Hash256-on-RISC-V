#!/usr/bin/env python3
"""
RISC-V CPU Pipeline Regression Test Suite

Automated regression testing framework with:
- Test discovery and execution
- Result aggregation and reporting
- Coverage analysis
- Defect tracking
- Golden model comparison
"""

import os
import sys
import subprocess
import json
import time
import re
from pathlib import Path
from dataclasses import dataclass, asdict
from enum import Enum
from datetime import datetime
import statistics
import sys
from pathlib import Path

# Add verification directory to sys.path to import reference model
sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from isa_reference_model import RV32IRefModel, load_hex_file
except ImportError:
    from verification.isa_reference_model import RV32IRefModel, load_hex_file

# ============================================================================
# Configuration
# ============================================================================

class TestStatus(Enum):
    """Test execution status"""
    PASSED = "PASSED"
    FAILED = "FAILED"
    TIMEOUT = "TIMEOUT"
    ERROR = "ERROR"
    SKIPPED = "SKIPPED"

@dataclass
class TestCase:
    """Individual test case"""
    name: str
    hex_file: str
    category: str
    description: str
    enabled: bool = True
    timeout_cycles: int = 1000
    expected_result: str = "PASS"

@dataclass
class TestResult:
    """Test execution result"""
    name: str
    status: str
    cycles: int
    duration_ms: float
    error_msg: str = None
    coverage: float = 0.0
    timestamp: str = None

# ============================================================================
# Test Suite Definition
# ============================================================================

REGRESSION_TESTS = [
    # Smoke Tests
    TestCase("smoke_nop", "programs/smoke_nop.hex", "smoke",
        "Basic fetch and halt loop smoke test"),
    
    # ISA Coverage - Arithmetic
    TestCase("alu_logic", "programs/alu_logic.hex", "isa_alu",
        "R-type ALU/logic operations (ADD, SUB, AND, OR, XOR, etc)"),
    TestCase("alu_imm_ext", "programs/alu_imm_ext.hex", "isa_alu",
        "OP-IMM extended coverage (XORI, SLTI, SLTIU, SRAI)"),
    
    # ISA Coverage - Control Flow
    TestCase("jal_flow", "programs/jal_flow.hex", "isa_control",
        "JAL skip/target control-flow behavior"),
    TestCase("jalr_selftest", "programs/jalr_selftest.hex", "isa_control",
        "JALR path and link register behavior"),
    TestCase("branch_beq_taken", "programs/branch_beq_taken.hex", "isa_control",
        "BEQ taken path"),
    TestCase("branch_bne_taken", "programs/branch_bne_taken.hex", "isa_control",
        "BNE taken path"),
    
    # ISA Coverage - Data Movement
    TestCase("auipc_basic", "programs/auipc_basic.hex", "isa_data",
        "AUIPC / PC-relative upper immediate path"),
    
    # ISA Coverage - Memory Operations
    TestCase("byte_half_store_load", "programs/byte_half_store_load.hex", "isa_memory",
        "Byte and halfword store/load sign-extension path"),
    TestCase("word_load_sign_ext", "programs/word_load_sign_ext.hex", "isa_memory",
        "Byte/halfword loads from a known 32-bit word pattern"),
    TestCase("mem_rw_basic", "programs/mem_rw_basic.hex", "isa_memory",
        "Basic RAM store/load/compare path"),
    
    # Cache Tests
    TestCase("dcache_write_hit", "programs/dcache_write_hit.hex", "cache",
        "D-cache write-hit update path"),
    TestCase("dcache_conflict_writeback", "programs/dcache_conflict_writeback.hex", "cache",
        "D-cache dirty eviction + write-back path"),
    
    # Negative Tests (if generated)
    TestCase("neg_unaligned_lw", "programs/neg/unaligned_lw.hex", "negative",
        "Unaligned load word access", enabled=True),
    TestCase("neg_unaligned_sw", "programs/neg/unaligned_sw.hex", "negative",
        "Store to unaligned address tests", enabled=True),
    TestCase("neg_boundary_values", "programs/neg/boundary_values.hex", "negative",
        "Boundary value arithmetic edge cases", enabled=True),
    TestCase("neg_rapid_deps", "programs/neg/rapid_dependencies.hex", "negative",
        "Pipeline hazard stress test", enabled=True),
    TestCase("neg_memory_stress", "programs/neg/memory_stress.hex", "negative",
        "Memory subsystem stress test", enabled=True),
    TestCase("neg_branch_stress", "programs/neg/branch_stress.hex", "negative",
        "Branch prediction stress test", enabled=True),
    TestCase("neg_shift_boundaries", "programs/neg/shift_boundaries.hex", "negative",
        "Shift amount boundary tests", enabled=True),
    TestCase("neg_register_edges", "programs/neg/register_edges.hex", "negative",
        "Register encoding edge cases", enabled=True),
    TestCase("neg_byte_halfword", "programs/neg/byte_halfword.hex", "negative",
        "Byte/halfword alignment tests", enabled=True),
]

# ============================================================================
# Regression Test Runner
# ============================================================================

class RegressionTestRunner:
    """Execute and track regression test suite"""
    
    def __init__(self, workspace_dir: str, vivado_bin: str = "vivado"):
        self.workspace = Path(workspace_dir)
        self.vivado_bin = vivado_bin
        self.results = []
        self.start_time = None
        self.sim_dir = self.workspace / "SoC.sim"
        self.snapshot_name = "tb_soc_top_sim"
        self.snapshot_ready = (self.workspace / "xsim.dir" / self.snapshot_name).exists()
        
    def discover_tests(self) -> int:
        """Discover available test files"""
        count = 0
        for test in REGRESSION_TESTS:
            hex_path = self.workspace / test.hex_file
            if hex_path.exists():
                count += 1
            else:
                print(f"⚠️  Test {test.name}: {hex_path} not found")
        return count
    
    def run_single_test(self, test: TestCase) -> TestResult:
        """Execute single test and collect result"""
        
        if not test.enabled:
            return TestResult(test.name, TestStatus.SKIPPED.value, 0, 0.0)
        
        hex_path = self.workspace / test.hex_file
        if not hex_path.exists():
            return TestResult(test.name, TestStatus.ERROR.value, 0, 0.0,
                error_msg=f"Hex file not found: {hex_path}")
        
        start_time = time.time()
        
        try:
            # Prepare simulation environment
            current_hex = self.workspace / "programs" / "_current.hex"
            
            # Copy test hex to current
            with open(hex_path, 'r') as src:
                content = src.read()
            with open(current_hex, 'w') as dst:
                dst.write(content)
            
            # Run vivado simulation
            status, cycle_count, output = self._run_vivado_sim(test)
            
            duration_ms = (time.time() - start_time) * 1000
            error_msg = None
            
            if status == TestStatus.PASSED:
                # Parse registers and PC from output
                reg_pattern = re.compile(r"\[REG\]\s+x(\d+)=0x([0-9a-fA-F]+)")
                pc_pattern = re.compile(r"\[PC\]\s+pc=0x([0-9a-fA-F]+)")
                
                hw_regs = [0] * 32
                hw_pc = None
                
                for line in output.splitlines():
                    reg_match = reg_pattern.search(line)
                    if reg_match:
                        reg_idx = int(reg_match.group(1))
                        reg_val = int(reg_match.group(2), 16)
                        if 0 <= reg_idx < 32:
                            hw_regs[reg_idx] = reg_val
                    
                    pc_match = pc_pattern.search(line)
                    if pc_match:
                        hw_pc = int(pc_match.group(1), 16)
                
                # Check that we parsed registers
                reg_lines_count = sum(1 for line in output.splitlines() if "[REG]" in line)
                if reg_lines_count < 32:
                    status = TestStatus.ERROR
                    error_msg = f"Failed to parse all registers from simulation output (only found {reg_lines_count}/32)"
                else:
                    # Run Reference Model
                    try:
                        imem = load_hex_file(str(hex_path))
                        ref_model = RV32IRefModel(imem)
                        
                        # Run reference model
                        ref_result = ref_model.run(max_cycles=test.timeout_cycles)
                        
                        # Compare states
                        mismatches = []
                        for i in range(1, 32):
                            if ref_model.regs[i] != hw_regs[i]:
                                mismatches.append(f"x{i}: expected 0x{ref_model.regs[i]:08x}, got 0x{hw_regs[i]:08x}")
                        
                        # Compare PC if parsed
                        if hw_pc is not None:
                            ref_pc_10bit = ref_model.pc & 0x3FF
                            if ref_pc_10bit != hw_pc:
                                mismatches.append(f"PC: expected 0x{ref_pc_10bit:03x}, got 0x{hw_pc:03x}")
                        
                        if mismatches:
                            status = TestStatus.FAILED
                            error_msg = "Golden Model mismatch:\n  " + "\n  ".join(mismatches)
                        else:
                            status = TestStatus.PASSED
                    except Exception as ref_err:
                        status = TestStatus.ERROR
                        error_msg = f"Reference model execution failed: {ref_err}"
            else:
                error_msg = output if status in (TestStatus.ERROR, TestStatus.FAILED, TestStatus.TIMEOUT) else None

            return TestResult(
                name=test.name,
                status=status.value if isinstance(status, TestStatus) else status,
                cycles=cycle_count,
                duration_ms=duration_ms,
                error_msg=error_msg,
                timestamp=datetime.now().isoformat()
            )
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            return TestResult(test.name, TestStatus.ERROR.value, 0, duration_ms,
                error_msg=str(e))
    
    def _run_vivado_sim(self, test: TestCase) -> tuple:
        """
        Run Vivado simulation for test.
        
        Returns:
            (status, cycle_count, output_msg)
        """
        print(f"  Running {test.name}...", end=" ", flush=True)

        if not self.sim_dir.exists():
            return TestStatus.ERROR, 0, f"Simulation directory not found: {self.sim_dir}"

        build_script = self.sim_dir / "build_and_run_programs.ps1"
        run_script = self.sim_dir / "run_programs.ps1"
        script = run_script if self.snapshot_ready else build_script

        if not script.exists():
            return TestStatus.ERROR, 0, f"Simulation script not found: {script}"

        env = os.environ.copy()
        env["PROGRAM_FILTER"] = Path(test.hex_file).name

        cmd = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(script),
        ]

        proc = subprocess.run(
            cmd,
            cwd=str(self.workspace),
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )

        output = ((proc.stdout or "") + "\n" + (proc.stderr or "")).strip()

        cycle_count = 0
        cycle_match = re.search(r"Halt loop detected at cycle=(\d+)", output)
        if cycle_match:
            cycle_count = int(cycle_match.group(1))

        if proc.returncode != 0:
            return TestStatus.ERROR, cycle_count, output

        if "[TB][PASS]" in output:
            self.snapshot_ready = True
            return TestStatus.PASSED, cycle_count, output

        if "[TB][TIMEOUT]" in output:
            return TestStatus.TIMEOUT, cycle_count, output

        return TestStatus.FAILED, cycle_count, output
    
    def run_all_tests(self) -> list:
        """Execute full regression suite"""
        
        self.start_time = time.time()
        self.results = []
        
        print("\n" + "="*70)
        print("Starting RISC-V CPU Pipeline Regression Test Suite")
        print("="*70 + "\n")
        
        for test in REGRESSION_TESTS:
            result = self.run_single_test(test)
            self.results.append(result)
            
            status_symbol = "[+]" if result.status == TestStatus.PASSED.value else "[-]"
            print(f"{status_symbol} [{result.status:8s}] {result.name:30s} {result.cycles:5d} cycles {result.duration_ms:8.1f}ms")
        
        return self.results
    
    def generate_report(self) -> dict:
        """Generate comprehensive test report"""
        
        total_time = time.time() - self.start_time
        
        # Categorize results
        passed = [r for r in self.results if r.status == TestStatus.PASSED.value]
        failed = [r for r in self.results if r.status == TestStatus.FAILED.value]
        timeout = [r for r in self.results if r.status == TestStatus.TIMEOUT.value]
        errors = [r for r in self.results if r.status == TestStatus.ERROR.value]
        skipped = [r for r in self.results if r.status == TestStatus.SKIPPED.value]
        
        # Calculate statistics
        durations = [r.duration_ms for r in self.results if r.duration_ms > 0]
        cycles = [r.cycles for r in self.results if r.cycles > 0]
        
        report = {
            "timestamp": datetime.now().isoformat(),
            "total_time_seconds": total_time,
            "summary": {
                "total_tests": len(self.results),
                "passed": len(passed),
                "failed": len(failed),
                "timeout": len(timeout),
                "errors": len(errors),
                "skipped": len(skipped),
                "pass_rate_percent": (len(passed) / (len(self.results) - len(skipped)) * 100) 
                    if (len(self.results) - len(skipped)) > 0 else 0
            },
            "performance": {
                "average_duration_ms": statistics.mean(durations) if durations else 0,
                "average_cycles": statistics.mean(cycles) if cycles else 0,
                "total_cycles": sum(cycles) if cycles else 0
            },
            "results_by_category": self._categorize_results(),
            "failing_tests": [asdict(r) for r in failed],
            "error_tests": [asdict(r) for r in errors],
            "all_results": [asdict(r) for r in self.results]
        }
        
        return report
    
    def _categorize_results(self) -> dict:
        """Group results by test category"""
        categories = {}
        for test in REGRESSION_TESTS:
            cat = test.category
            if cat not in categories:
                categories[cat] = {"total": 0, "passed": 0, "failed": 0}
            
            matching = [r for r in self.results if r.name == test.name]
            if matching:
                categories[cat]["total"] += 1
                if matching[0].status == TestStatus.PASSED.value:
                    categories[cat]["passed"] += 1
                else:
                    categories[cat]["failed"] += 1
        
        return categories
    
    def print_summary(self, report: dict):
        """Print human-readable summary"""
        
        summary = report["summary"]
        perf = report["performance"]
        
        print("\n" + "="*70)
        print("TEST SUITE SUMMARY")
        print("="*70)
        
        print(f"\nTest Results:")
        print(f"  Total:     {summary['total_tests']}")
        print(f"  Passed:    {summary['passed']} [OK]")
        print(f"  Failed:    {summary['failed']} [FAIL]")
        print(f"  Timeout:   {summary['timeout']}")
        print(f"  Errors:    {summary['errors']}")
        print(f"  Skipped:   {summary['skipped']}")
        print(f"  Pass Rate: {summary['pass_rate_percent']:.1f}%")
        
        print(f"\nPerformance Metrics:")
        print(f"  Total Time:         {report['total_time_seconds']:.2f}s")
        print(f"  Average Duration:   {perf['average_duration_ms']:.1f}ms")
        print(f"  Average Cycles:     {perf['average_cycles']:.0f}")
        print(f"  Total Cycles:       {perf['total_cycles']}")
        
        print(f"\nCoverage by Category:")
        for cat, stats in report["results_by_category"].items():
            if stats["total"] > 0:
                rate = stats["passed"] / stats["total"] * 100
                print(f"  {cat:20s}: {stats['passed']:2d}/{stats['total']:2d} ({rate:5.1f}%)")
        
        if report["failing_tests"]:
            print(f"\nFailing Tests:")
            for test in report["failing_tests"]:
                print(f"  - {test['name']}: {test['error_msg']}")

        timeout_tests = [r for r in report["all_results"] if r["status"] == TestStatus.TIMEOUT.value]
        if timeout_tests:
            print(f"\nTimeout Tests:")
            for test in timeout_tests:
                print(f"  - {test['name']}: timeout detected")
        
        print("\n" + "="*70)
        has_issue = (summary['failed'] > 0) or (summary['errors'] > 0) or (summary['timeout'] > 0)
        print(f"Overall: {'PASS' if not has_issue else 'FAIL'}")
        print("="*70 + "\n")
    
    def save_report(self, filename: str = "regression_report.json"):
        """Save report to JSON file"""
        report = self.generate_report()
        
        output_path = self.workspace / filename
        with open(output_path, 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"Report saved to: {output_path}")
        return output_path

# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    if len(sys.argv) < 2:
        print("Usage: run_regression.py <workspace_dir> [vivado_path]")
        sys.exit(1)
    
    workspace = sys.argv[1]
    vivado_bin = sys.argv[2] if len(sys.argv) > 2 else "vivado"
    
    runner = RegressionTestRunner(workspace, vivado_bin)
    
    # Discover tests
    test_count = runner.discover_tests()
    print(f"Discovered {test_count} tests\n")
    
    # Run regression suite
    runner.run_all_tests()
    
    # Generate and print report
    report = runner.generate_report()
    runner.print_summary(report)
    
    # Save report
    runner.save_report()
    
    # Exit with appropriate code
    summary = report["summary"]
    has_issue = (summary["failed"] > 0) or (summary["errors"] > 0) or (summary["timeout"] > 0)
    return 0 if not has_issue else 1


if __name__ == "__main__":
    sys.exit(main())
