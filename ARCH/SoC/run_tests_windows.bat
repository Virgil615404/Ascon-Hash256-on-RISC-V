@echo off
REM RISC-V CPU Pipeline Regression Test Runner (Windows Batch)
REM Simple batch script for Windows verification

setlocal enabledelayedexpansion

echo.
echo ========================================================
echo RISC-V CPU Pipeline Regression Test Suite (Windows Batch)
echo ========================================================
echo.

REM Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo Error: Python not found in PATH
    exit /b 1
)
python --version
echo.

REM Check verification files exist
if not exist verification\isa_reference_model.py (
    echo Error: isa_reference_model.py not found
    exit /b 1
)
if not exist verification\run_regression.py (
    echo Error: run_regression.py not found
    exit /b 1
)
echo Verification framework found
echo.

REM Create neg directory
if not exist programs\neg mkdir programs\neg

echo ========================================================
echo STEP 1: Generating Negative Tests
echo ========================================================
echo.

python verification\negative_tests\negative_test_generator.py boundary_values programs\neg\boundary_values.hex
python verification\negative_tests\negative_test_generator.py rapid_dependencies programs\neg\rapid_dependencies.hex
python verification\negative_tests\negative_test_generator.py memory_stress programs\neg\memory_stress.hex
python verification\negative_tests\negative_test_generator.py unaligned_lw programs\neg\unaligned_lw.hex
echo.

echo ========================================================
echo STEP 2: Running ISA Reference Model Tests
echo ========================================================
echo.

setlocal
set "refPassed=0"
set "refFailed=0"

for %%T in (alu_logic jal_flow branch_beq_taken) do (
    if exist programs\%%T.hex (
        echo Testing %%T...
        python verification\isa_reference_model.py programs\%%T.hex >nul 2>&1
        if errorlevel 1 (
            set /a refFailed=!refFailed!+1
            echo   FAIL
        ) else (
            set /a refPassed=!refPassed!+1
            echo   PASS
        )
    )
)
echo.
echo Reference Model Results: !refPassed! PASS, !refFailed! FAIL
echo.

echo ========================================================
echo STEP 3: Running Full Regression Test Suite
echo ========================================================
echo.

python verification\run_regression.py .
set "regExit=%errorlevel%"

REM Check if regression_report.json exists
if exist regression_report.json (
    echo.
    echo ========================================================
    echo TEST RESULTS SUMMARY
    echo ========================================================
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$r = Get-Content regression_report.json | ConvertFrom-Json; Write-Host ('timestamp: ' + $r.timestamp); Write-Host ('total_tests: ' + $r.summary.total_tests); Write-Host ('passed: ' + $r.summary.passed); Write-Host ('failed: ' + $r.summary.failed); Write-Host ('timeout: ' + $r.summary.timeout); Write-Host ('errors: ' + $r.summary.errors); Write-Host ('skipped: ' + $r.summary.skipped); Write-Host ('pass_rate_percent: ' + [math]::Round($r.summary.pass_rate_percent, 1))"
    echo.
    echo Report saved to: regression_report.json
    echo.
    if %regExit% equ 0 if !refFailed! equ 0 (
        echo ========================================================
        echo OVERALL RESULT: PASS
        echo ========================================================
        echo.
        exit /b 0
    ) else (
        echo ========================================================
        echo OVERALL RESULT: FAIL
        echo ========================================================
        echo.
        exit /b 1
    )
) else (
    echo.
    echo Error: regression_report.json not generated
    exit /b 1
)
