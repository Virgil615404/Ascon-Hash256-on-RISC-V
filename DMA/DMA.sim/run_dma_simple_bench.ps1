$ErrorActionPreference = "Stop"

$repoRoot = Join-Path $PSScriptRoot ".."
$srcRoot = Join-Path $repoRoot "DMA.srcs"
$asconRoot = Join-Path $srcRoot "peripherals\asconhash256"
$dmaRoot = Join-Path $srcRoot "peripherals\dma"
$setupScript = Join-Path $PSScriptRoot "setup_vivado_env.ps1"
$tbFile = Join-Path $PSScriptRoot "tb_dma_simple_bench.sv"

if (-not (Get-Command xvlog -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path $setupScript)) {
        throw "Missing setup script: $setupScript"
    }
    . $setupScript
}

Push-Location $repoRoot
try {
    $includeDirs = @(
        $srcRoot,
        (Join-Path $srcRoot "bus"),
        (Join-Path $srcRoot "bus\axil"),
        (Join-Path $srcRoot "memory"),
        $asconRoot,
        $dmaRoot,
        $PSScriptRoot
    )

    $srcFiles = @(
        (Join-Path $srcRoot "memory\soc_ram.v"),
        (Join-Path $srcRoot "bus\axil\axil_ram_slave.sv"),
        (Join-Path $asconRoot "ascon_core.sv"),
        (Join-Path $dmaRoot "axil_dma_asconhash256.sv"),
        $tbFile
    )

    Write-Host "[1/3] xvlog"
    $xvlogArgs = @("-sv", "--uvm_version", "1.2")
    foreach ($inc in $includeDirs) {
        if (Test-Path $inc) {
            $xvlogArgs += "-i"
            $xvlogArgs += $inc
        }
    }
    $xvlogArgs += $srcFiles
    & xvlog @xvlogArgs
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

    Write-Host "[2/3] xelab"
    & xelab tb_dma_simple_bench -s tb_dma_simple_bench_sim --timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

    Write-Host "[3/3] xsim"
    & xsim tb_dma_simple_bench_sim --R
    if ($LASTEXITCODE -ne 0) { throw "xsim failed" }
}
finally {
    Pop-Location
}