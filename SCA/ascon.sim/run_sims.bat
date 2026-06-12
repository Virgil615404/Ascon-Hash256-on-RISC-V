@echo off
setlocal enabledelayedexpansion

echo ====================================================
echo  Ascon Simulation Runner Batch Wrapper
echo ====================================================

:: Check if Python is installed
python --version >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Python is not installed or not found in system PATH.
    echo Please install Python 3 and add it to PATH.
    exit /b 1
)

:: Run the python script
python "%~dp0run_sims.py" %*

if %ERRORLEVEL% neq 0 (
    echo [ERROR] Simulation runner script failed.
    exit /b %ERRORLEVEL%
)

echo [INFO] Completed successfully.
