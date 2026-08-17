# Minesweeper FPGA submission — SPEED-10

Cyclone IV E `EP4CE30F23I7`（MU500、20 MHz）向けの提出用FPGA一式です。

## SPEED-10の方針

- probability feedback 1〜8回目は通常実行
- 9回目以降は `opened_safe < total_safe / 2` の間だけ継続
- RTLでは除算を避け、同値な
  `2 * observed_safe_count < width * height - total_mines` を使用
- 4-bit feedbackカウンタは15で飽和し、折り返さない
- 低スコア盤向けの辺中央rescueを維持

## 公式1000盤結果

| 項目 | 値 |
|---|---:|
| 平均スコア | 0.8701659 |
| score_scaled合計 | 8,701,659 |
| opened safe合計 | 98,066 |
| opened mine合計 | 1,232 |
| stalled盤面数 | 228 |
| selections合計 | 48,446 |
| solver cycles合計 | 71,246,919 |

MU500実機1000盤はシミュレーションと全結果フィールドで一致し、transport
errorとJTAG retryはいずれも0でした。

## Quartus結果

- Quartus Prime Lite 24.1std
- Logic elements: 23,363 / 28,848（81%）
- Registers: 8,536
- Memory bits: 38,943
- Embedded multiplier 9-bit elements: 17 / 132
- Worst setup slack: +6.780 ns
- Worst hold slack: +0.112 ns
- Full compilation: 0 errors

## ディレクトリ構成

```text
fpga/
├─ rtl/                              Verilog/SystemVerilog一式
├─ sim/
│  ├─ official.f                     Icarus Verilog file list
│  ├─ tb_official_board_file.sv      公式盤テストベンチ
│  ├─ run_official_file.ps1          シミュレーション実行
│  └─ jtag_official_runner.tcl       MU500 JTAG実行
├─ official/
│  └─ board_pack_1000_fpga.txt
├─ quartus/
│  ├─ minesweeper_submission_local_mu500.qpf
│  ├─ minesweeper_submission_local_mu500.qsf
│  ├─ minesweeper_mu500.qsf
│  └─ minesweeper_mu500.sdc
├─ deliverables/
│  └─ minesweeper_submission_local_mu500.sof
├─ minesweeper_fpga_result.xlsx
└─ README.md
```

## シミュレーション

リポジトリのルートから実行します。

```powershell
.\fpga\sim\run_official_file.ps1 `
  -BoardFile .\fpga\official\board_pack_1000_fpga.txt `
  -ResultCsv fpga\speed10_simulation_1000.csv `
  -MaxBoards 1000 `
  -MaxProbabilityGuesses 15 `
  -BaseProbabilityGuesses 8 `
  -SaturatingHalfSafeFeedback `
  -LowScoreEdgeRescue `
  -LowScoreRescueSafeThreshold 16 `
  -Deterministic `
  -BuildTag speed10
```

必要なツールはIcarus Verilogの`iverilog`と`vvp`です。付属スクリプトは
`C:\msys64\ucrt64\bin`を既定の配置として使用します。

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
  fpga/speed10_hardware_1000.csv 1000 0 fast
```

## 提出物ハッシュ（SHA-256）

| ファイル | SHA-256 |
|---|---|
| SOF | `FE012D0E208C84CF70724A32A48E57CA7E5E5E12ACBF10728EED7DF0B1A3F69E` |
| Excel | `EC6BAD7C7CD8B7DF3BF3FC676A960813DED9040B3E3F7F810C66E3035929AEEA` |
