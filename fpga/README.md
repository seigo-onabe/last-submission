# Minesweeper FPGA submission

Cyclone IV E `EP4CE30F23I7`（MU500、20 MHz）向けの提出用FPGA一式です。


## ディレクトリ構成

```text
fpga/
├─ rtl/                              Verilog/SystemVerilog一式
├─ sim/                              シミュレーション・JTAG実行一式
├─ official/                         公式1000盤
├─ quartus/                          Quartusプロジェクト
├─ deliverables/                     提出用SOF
├─ minesweeper_fpga_result.xlsx      結果集計
└─ README.md
```

## シミュレーション

リポジトリのルートから実行します。

```powershell
.\fpga\sim\run_official_file.ps1 `
  -BoardFile .\fpga\official\board_pack_1000_fpga.txt `
  -ResultCsv fpga\simulation_1000.csv `
  -MaxBoards 1000 `
  -MaxProbabilityGuesses 15 `
  -BaseProbabilityGuesses 8 `
  -SaturatingHalfSafeFeedback `
  -LowScoreEdgeRescue `
  -LowScoreRescueSafeThreshold 16 `
  -Deterministic `
  -BuildTag speed11
```

必要なツールはIcarus Verilogの`iverilog`と`vvp`です。

## Quartusコンパイル

```powershell
quartus_sh --flow compile .\fpga\quartus\minesweeper_submission_local_mu500
```

トップレベルentityは`minesweeper_jtag_submission_local_top`です。

## MU500への書き込みと実機試験

```powershell
quartus_pgm -m jtag -o "p;fpga\deliverables\minesweeper_submission_local_mu500.sof@1"

quartus_stp -t fpga/sim/jtag_official_runner.tcl `
  fpga/official/board_pack_1000_fpga.txt `
  fpga/hardware_1000.csv 1000 0 fast
```
