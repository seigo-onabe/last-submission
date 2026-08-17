param(
    [Parameter(Mandatory=$true)][string]$BoardFile,
    [string]$ResultCsv = 'fpga\sim\minesweeper_results.csv',
    [int]$MaxBoards = 2147483647,
    [int]$StartBoard = 0,
    [int]$MaxProbabilityGuesses = 4,
    [switch]$AdaptiveFeedback,
    [switch]$SaturatingHalfSafeFeedback,
    [int]$BaseProbabilityGuesses = 8,
    [int]$AdaptiveFeedbackSafeThreshold = 32,
    [switch]$LowScoreEdgeRescue,
    [int]$LowScoreRescueSafeThreshold = 16,
    [string]$BuildTag = '',
    [switch]$Deterministic,
    [switch]$Profile,
    [string]$ProfileEventCsv = '',
    [string]$FrontierEventCsv = ''
)

$ErrorActionPreference = 'Stop'
if ($StartBoard -lt 0 -or $MaxBoards -lt 0) {
    throw 'StartBoard and MaxBoards must be non-negative.'
}
$repoDir = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$fpgaDir = Join-Path $repoDir 'fpga'
$buildDir = Join-Path $fpgaDir 'sim\build'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

$iverilog = 'C:\msys64\ucrt64\bin\iverilog.exe'
$vvp = 'C:\msys64\ucrt64\bin\vvp.exe'
$iverilogBaseArgs = @()
if (-not (Test-Path -LiteralPath $iverilog) -or
    -not (Test-Path -LiteralPath $vvp)) {
    throw 'Icarus Verilog was not found under C:\msys64\ucrt64\bin.'
}
$env:PATH = "$(Split-Path -Parent $iverilog);$env:PATH"

$boardPath = (Resolve-Path -LiteralPath $BoardFile).Path
$resultPath = if ([System.IO.Path]::IsPathRooted($ResultCsv)) {
    [System.IO.Path]::GetFullPath($ResultCsv)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoDir $ResultCsv))
}
$resultParent = Split-Path -Parent $resultPath
New-Item -ItemType Directory -Force -Path $resultParent | Out-Null
$safeBuildTag = $BuildTag -replace '[^A-Za-z0-9_-]', '_'
$tagSuffix = if ($safeBuildTag) { "_$safeBuildTag" } else { '' }
$outputName = if ($Deterministic) {
    "tb_official_board_file_deterministic$tagSuffix.vvp"
} else {
    "tb_official_board_file$tagSuffix.vvp"
}
$output = Join-Path $buildDir $outputName
Push-Location $fpgaDir
try {
    $compileArgs = @('-g2012','-Wall','-s','tb_official_board_file',
                     '-c','sim/official.f','-o',$output)
    if ($Deterministic) {
        $compileArgs += '-Ptb_official_board_file.DETERMINISTIC_SOLVER=1'
        $compileArgs += "-Ptb_official_board_file.MAX_PROBABILITY_GUESSES=$MaxProbabilityGuesses"
        $compileArgs += "-Ptb_official_board_file.ENABLE_ADAPTIVE_FEEDBACK=$([int]$AdaptiveFeedback.IsPresent)"
        $compileArgs += "-Ptb_official_board_file.ENABLE_SATURATING_HALF_SAFE_FEEDBACK=$([int]$SaturatingHalfSafeFeedback.IsPresent)"
        $compileArgs += "-Ptb_official_board_file.BASE_PROBABILITY_GUESSES=$BaseProbabilityGuesses"
        $compileArgs += "-Ptb_official_board_file.ADAPTIVE_FEEDBACK_SAFE_THRESHOLD=$AdaptiveFeedbackSafeThreshold"
        $compileArgs += "-Ptb_official_board_file.ENABLE_LOW_SCORE_EDGE_RESCUE=$([int]$LowScoreEdgeRescue.IsPresent)"
        $compileArgs += "-Ptb_official_board_file.LOW_SCORE_RESCUE_SAFE_THRESHOLD=$LowScoreRescueSafeThreshold"
    }
    if ($Profile) {
        $compileArgs += '-DSIM_PROFILE'
    }
    & $iverilog @iverilogBaseArgs @compileArgs
    if ($LASTEXITCODE -ne 0) { throw "iverilog failed: $LASTEXITCODE" }
    $runArgs = @($output, "+BOARD_FILE=$boardPath",
                 "+RESULT_CSV=$resultPath", "+START_BOARD=$StartBoard",
                 "+MAX_BOARDS=$MaxBoards")
    if ($ProfileEventCsv) {
        $profileEventPath = if ([System.IO.Path]::IsPathRooted($ProfileEventCsv)) {
            [System.IO.Path]::GetFullPath($ProfileEventCsv)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $repoDir $ProfileEventCsv))
        }
        $profileEventParent = Split-Path -Parent $profileEventPath
        New-Item -ItemType Directory -Force -Path $profileEventParent | Out-Null
        $runArgs += "+PROFILE_EVENT_CSV=$profileEventPath"
    }
    if ($FrontierEventCsv) {
        $frontierEventPath = if ([System.IO.Path]::IsPathRooted($FrontierEventCsv)) {
            [System.IO.Path]::GetFullPath($FrontierEventCsv)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $repoDir $FrontierEventCsv))
        }
        New-Item -ItemType Directory -Force `
            -Path (Split-Path -Parent $frontierEventPath) | Out-Null
        $runArgs += "+FRONTIER_EVENT_CSV=$frontierEventPath"
    }
    & $vvp @runArgs
    if ($LASTEXITCODE -ne 0) { throw "simulation failed: $LASTEXITCODE" }
} finally {
    Pop-Location
}
Write-Host "CSV: $resultPath"
