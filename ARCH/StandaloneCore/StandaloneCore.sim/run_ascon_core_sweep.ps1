$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'StandaloneCore.srcs'
$asconRoot = Join-Path $srcRoot 'peripherals\asconhash256'
$tbFile = Join-Path $PSScriptRoot 'tb_ascon_core_bench.sv'
$tbBak = "$tbFile.bak"
$setupScript = Join-Path $repoRoot 'DMA\DMA.sim\setup_vivado_env.ps1'

if (-not (Get-Command xvlog -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path $setupScript)) {
        throw "Missing setup script: $setupScript"
    }
    . $setupScript
}

function Set-TbConfig([string]$Path, [int]$PayloadBytes, [int]$MaxCycles) {
    $txt = Get-Content -Raw $Path
    $txt = $txt -replace 'localparam int TB_PAYLOAD_BYTES = \d+;', ("localparam int TB_PAYLOAD_BYTES = {0};" -f $PayloadBytes)
    $txt = $txt -replace 'localparam int TB_MAX_CYCLES = \d+;', ("localparam int TB_MAX_CYCLES = {0};" -f $MaxCycles)
    Set-Content -Path $Path -Value $txt
}

if (-not (Test-Path $tbBak)) {
    Copy-Item $tbFile $tbBak
}

$payloads = @(1,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384)
$maxCycles = 50000
$csvPath = Join-Path $PSScriptRoot 'core_results.csv'
$e2eCsvPath = Join-Path $PSScriptRoot 'core_results_e2e.csv'

Push-Location $repoRoot
try {
    $includeDirs = @(
        $srcRoot,
        (Join-Path $srcRoot 'peripherals'),
        $asconRoot,
        $PSScriptRoot
    )

    $srcFiles = @(
        (Join-Path $asconRoot 'config.sv'),
        (Join-Path $asconRoot 'functions.sv'),
        (Join-Path $asconRoot 'asconp.sv'),
        (Join-Path $asconRoot 'ascon_core.sv'),
        $tbFile
    )

    $xvlogArgs = @('-sv')
    foreach ($inc in $includeDirs) {
        if (Test-Path $inc) {
            $xvlogArgs += '-i'
            $xvlogArgs += $inc
        }
    }

    "payload_bytes,active_cycles,bytes_per_cycle,throughput_mb_s" | Out-File -FilePath $csvPath -Encoding utf8
    "payload_bytes,e2e_cycles,bytes_per_cycle,throughput_mb_s" | Out-File -FilePath $e2eCsvPath -Encoding utf8

    foreach ($payload in $payloads) {
        Write-Host "=== Payload $payload bytes ==="

        Set-TbConfig -Path $tbFile -PayloadBytes $payload -MaxCycles $maxCycles

        Write-Host '[1/3] xvlog'
        $xvlogArgsRun = @($xvlogArgs + $srcFiles)
        & xvlog @xvlogArgsRun
        if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }

        Write-Host '[2/3] xelab'
        & xelab tb_ascon_core_bench -s tb_ascon_core_bench_sim --timescale 1ns/1ps
        if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }

        Write-Host '[3/3] xsim'
        $runOutput = & xsim tb_ascon_core_bench_sim --R 2>&1 | Out-String

        $unifiedMatch = [regex]::Match($runOutput, '(?m)\[TB\]\[CORE\]\[PERF_UNIFIED\].*bytes=(\d+) cycles=(\d+) bytes_per_cycle=(\d+\.\d+) throughput=(\d+\.\d+)')
        $e2eMatch = [regex]::Match($runOutput, '(?m)\[TB\]\[CORE\]\[PERF_E2E\].*bytes=(\d+) cycles=(\d+) bytes_per_cycle=(\d+\.\d+) throughput=(\d+\.\d+)')

        if (-not $unifiedMatch.Success -or -not $e2eMatch.Success) {
            throw "Failed to parse perf lines for payload $payload"
        }

        "$($unifiedMatch.Groups[1].Value),$($unifiedMatch.Groups[2].Value),$($unifiedMatch.Groups[3].Value),$($unifiedMatch.Groups[4].Value)" | Out-File -FilePath $csvPath -Append -Encoding utf8
        "$($e2eMatch.Groups[1].Value),$($e2eMatch.Groups[2].Value),$($e2eMatch.Groups[3].Value),$($e2eMatch.Groups[4].Value)" | Out-File -FilePath $e2eCsvPath -Append -Encoding utf8

        $summaryLines = $runOutput | Select-String -Pattern '\[TB\]\[CORE\]\[(PERF_UNIFIED|PERF_E2E)\]'
        foreach ($line in $summaryLines) {
            Write-Host $line.Line
        }
    }

    Write-Host "Sweep finished. CSVs: $csvPath, $e2eCsvPath"
}
finally {
    if (Test-Path $tbBak) {
        Copy-Item $tbBak $tbFile -Force
    }
    Pop-Location
}