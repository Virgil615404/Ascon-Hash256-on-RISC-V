param(
    [string]$VivadoHome
)

$ErrorActionPreference = "Stop"

function Resolve-VivadoHome {
    param([string]$UserPath)

    if ($UserPath -and (Test-Path $UserPath)) {
        return (Resolve-Path $UserPath).Path
    }

    $envCandidates = @($env:XILINX_VIVADO, $env:VIVADO_HOME)
    foreach ($candidate in $envCandidates) {
        if ($candidate -and (Test-Path (Join-Path $candidate "bin\\xsim.bat"))) {
            return (Resolve-Path $candidate).Path
        }
    }

    $roots = @(
        "C:\\Xilinx\\Vivado",
        "D:\\Xilinx\\Vivado",
        "C:\\AMD\\Vivado",
        "D:\\AMD\\Vivado"
    )

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) {
            continue
        }

        $versions = Get-ChildItem -Path $root -Directory | Sort-Object Name -Descending
        foreach ($v in $versions) {
            $xsimBat = Join-Path $v.FullName "bin\\xsim.bat"
            if (Test-Path $xsimBat) {
                return $v.FullName
            }
        }
    }

    $nestedRoots = @(
        "C:\\Xilinx",
        "D:\\Xilinx",
        "C:\\AMD",
        "D:\\AMD"
    )

    foreach ($root in $nestedRoots) {
        if (-not (Test-Path $root)) {
            continue
        }

        $versionDirs = Get-ChildItem -Path $root -Directory | Sort-Object Name -Descending
        foreach ($v in $versionDirs) {
            $vivadoHome = Join-Path $v.FullName "Vivado"
            $xsimBat = Join-Path $vivadoHome "bin\\xsim.bat"
            if (Test-Path $xsimBat) {
                return $vivadoHome
            }
        }
    }

    return $null
}

$resolvedVivadoHome = Resolve-VivadoHome -UserPath $VivadoHome
if (-not $resolvedVivadoHome) {
    throw "Vivado installation not found. Pass -VivadoHome or set XILINX_VIVADO/VIVADO_HOME."
}

$binPath = Join-Path $resolvedVivadoHome "bin"
if (-not (Test-Path (Join-Path $binPath "xsim.bat"))) {
    throw "Invalid Vivado path: $resolvedVivadoHome (bin\\xsim.bat not found)."
}

$pathParts = $env:Path -split ';'
if (-not ($pathParts -contains $binPath)) {
    $env:Path = "$binPath;$env:Path"
}

$env:VIVADO_HOME = $resolvedVivadoHome
$env:XILINX_VIVADO = $resolvedVivadoHome

$xvlogCmd = Get-Command xvlog -ErrorAction SilentlyContinue
$xelabCmd = Get-Command xelab -ErrorAction SilentlyContinue
$xsimCmd = Get-Command xsim -ErrorAction SilentlyContinue
if (-not ($xvlogCmd -and $xelabCmd -and $xsimCmd)) {
    throw "Vivado tools still unavailable after setup. Check installation integrity."
}

Write-Host "Vivado environment ready"
Write-Host "VIVADO_HOME=$resolvedVivadoHome"
Write-Host "xvlog=$($xvlogCmd.Source)"
Write-Host "xelab=$($xelabCmd.Source)"
Write-Host "xsim=$($xsimCmd.Source)"