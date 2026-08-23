$ErrorActionPreference = 'Stop'

$reportDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$miKTeXBin = Join-Path $env:LOCALAPPDATA 'Programs\MiKTeX\miktex\bin\x64'

function Resolve-TeXCommand([string]$name) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidate = Join-Path $miKTeXBin "$name.exe"
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    throw "$name was not found. Install MiKTeX, then run this script again."
}

$luaLaTeX = Resolve-TeXCommand 'lualatex'
$bibTeX = Resolve-TeXCommand 'bibtex'

Push-Location $reportDir
try {
    & $luaLaTeX --enable-installer --interaction=nonstopmode --halt-on-error main.tex
    if ($LASTEXITCODE -ne 0) { throw "LuaLaTeX failed (first pass)." }

    & $bibTeX main
    if ($LASTEXITCODE -ne 0) { throw "BibTeX failed." }

    1..2 | ForEach-Object {
        & $luaLaTeX --enable-installer --interaction=nonstopmode --halt-on-error main.tex
        if ($LASTEXITCODE -ne 0) { throw "LuaLaTeX failed (final pass $_)." }
    }

    Write-Host "Built: $(Join-Path $reportDir 'main.pdf')"
}
finally {
    Pop-Location
}
