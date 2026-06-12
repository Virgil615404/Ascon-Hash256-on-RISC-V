$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'MMIO.srcs'
$tbFile = Join-Path $PSScriptRoot 'tb_ascon_mmio_bench.sv'
$setupScript = Join-Path $PSScriptRoot 'setup_vivado_env.ps1'

$includeDirs = @(
    $srcRoot,
    (Join-Path $srcRoot 'bus'),
    (Join-Path $srcRoot 'cpu'),
    (Join-Path $srcRoot 'memory'),
    (Join-Path $srcRoot 'peripherals'),
    (Join-Path $srcRoot 'top'),
    $PSScriptRoot
)

$srcFiles = @()
$srcFiles += Get-ChildItem -Path $srcRoot -Recurse -Include *.v,*.sv | Select-Object -ExpandProperty FullName
$srcFiles += $tbFile

if (-not (Get-Command xvlog -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path $setupScript)) {
        throw "Missing setup script: $setupScript"
    }
    . $setupScript
}

Push-Location $repoRoot
try {
    $xvlogArgs = @('-sv')
    foreach ($inc in $includeDirs) {
        $xvlogArgs += '-i'
        $xvlogArgs += $inc
    }
    $xvlogArgs += $srcFiles

    Write-Host '[1/3] xvlog'
    & xvlog @xvlogArgs
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }

    Write-Host '[2/3] xelab'
    & xelab tb_ascon_mmio_bench -s tb_ascon_mmio_bench_sim --timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }

    Write-Host '[3/3] xsim'
    & xsim --runall tb_ascon_mmio_bench_sim
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed' }
}
finally {
    Pop-Location
}