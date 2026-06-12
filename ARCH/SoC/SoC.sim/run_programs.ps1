$ErrorActionPreference = "Stop"

$repoRoot = Join-Path $PSScriptRoot ".."
$programDir = Join-Path $PSScriptRoot "..\programs"
$tbName = "tb_soc_top"
$cycles = 1000
$activeHex = Join-Path $programDir "_current.hex"
$programFilter = $env:PROGRAM_FILTER

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
        Write-Error "No .hex programs matched PROGRAM_FILTER='$programFilter' under $programDir"
    }
    Write-Error "No .hex programs found under $programDir"
}

Write-Host "Found $($programs.Count) programs"

Push-Location $repoRoot

try {
    foreach ($p in $programs) {
        Write-Host "`n=== Running $($p.Name) ==="

        Copy-Item -Path $p.FullName -Destination $activeHex -Force
        $xsimArgs = @(
            "--runall",
            "${tbName}_sim"
        )

        & xsim @xsimArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Simulation failed for $($p.Name)"
        }
    }
}
finally {
    Pop-Location
}

Write-Host "`nAll programs finished."
