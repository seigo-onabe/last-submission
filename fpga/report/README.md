# FPGA report

`main.tex` is the root of the Japanese LaTeX report.

## Build

MiKTeX 25.12 or another LuaLaTeX distribution is required.  On Windows, run:

```powershell
.\build.ps1
```

The script locates MiKTeX, enables automatic package installation, runs LuaLaTeX,
BibTeX, and the final two LuaLaTeX passes, then writes `main.pdf` in this folder.
The document uses `ltjsreport`, TikZ, pgfplots, and standard MiKTeX/TeX Live
packages.
