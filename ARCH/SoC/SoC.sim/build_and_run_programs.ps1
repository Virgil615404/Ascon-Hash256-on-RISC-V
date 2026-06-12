$ErrorActionPreference = "Stop"

$repoRoot = Join-Path $PSScriptRoot ".."
$srcRoot = Join-Path $repoRoot "SoC.srcs"
$tbFile = Join-Path $PSScriptRoot "tb_soc_top.sv"
$programDir = Join-Path $repoRoot "programs"

$simTop = "tb_soc_top"
$snapshot = "tb_soc_top_sim"
$cycles = 1000
$activeHex = Join-Path $programDir "_current.hex"
$programFilter = $env:PROGRAM_FILTER
$includeDirs = @(
    $srcRoot,
    (Join-Path $srcRoot "bus"),
    (Join-Path $srcRoot "cpu"),
    (Join-Path $srcRoot "memory"),
    (Join-Path $srcRoot "peripherals"),
    (Join-Path $srcRoot "top")
)

Push-Location $repoRoot

try {
    Write-Host "[1/3] Collecting source files..."
    $srcFiles = @()
    $srcFiles += Get-ChildItem -Path $srcRoot -Recurse -Include *.v,*.sv | Select-Object -ExpandProperty FullName
    $srcFiles += $tbFile

    Write-Host "[2/3] Compiling (xvlog)..."
    $xvlogArgs = @()
    $xvlogArgs += "-sv"
    foreach ($inc in $includeDirs) {
        if (Test-Path $inc) {
            $xvlogArgs += "-i"
            $xvlogArgs += $inc
        }
    }
    $xvlogArgs += $srcFiles

    & xvlog @xvlogArgs
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed"
    }

    Write-Host "[3/3] Elaborating (xelab)..."
    & xelab $simTop -s $snapshot --timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) {
        throw "xelab failed"
    }

    $programs = Get-ChildItem -Path $programDir -Recurse -Filter *.hex |
        Where-Object { $_.Name -ne "_current.hex" } |
        Sort-Object FullName

    if ($programFilter) {
        $programs = $programs | Where-Object {
            ($_.Name -like $programFilter) -or
            ($_.FullName -like ("*" + $programFilter + "*"))
        }
    }

    if ($programs.Count -eq 0) {
        if ($programFilter) {
            throw "No .hex files matched PROGRAM_FILTER='$programFilter' in $programDir"
        }
        throw "No .hex files found in $programDir"
    }

    foreach ($p in $programs) {
        Write-Host "`n=== Running $($p.Name) ==="
        Copy-Item -Path $p.FullName -Destination $activeHex -Force
        $xsimArgs = @(
            "--runall",
            $snapshot
        )
        & xsim @xsimArgs
        if ($LASTEXITCODE -ne 0) {
            throw "xsim failed for $($p.Name)"
        }
    }

    Write-Host "`nAll program regressions finished."
}
finally {
    Pop-Location
}
