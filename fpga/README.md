# Minesweeper FPGA submission — SPEED-11

Cyclone IV E `EP4CE30F23I7`（MU500、20 MHz）向けの提出用FPGA一式です。

## SPEED-11の構成

- `MAX_COLLECTOR_CONSTRAINTS = 8` の決定論的solver
- probability feedbackは最大15回、通常実行は8回
- 低スコア盤向けの辺中央rescueを維持
- 4-bit feedbackカウンタは15で飽和し、折り返さない

## 公式1000盤結果

| 項目 | 値 |
|---|---:|
| 平均スコア | 0.9038487 |
| score_scaled合計 | 9,038,487 |
| opened safe合計 | 101,775 |
| opened mine合計 | 1,233 |
| stalled盤面数 | 138 |
| selections合計 | 51,281 |
| solver cycles合計 | 81,110,615 |

MU500実機1000盤はシミュレーションと14フィールドで全結果が一致し、transport
errorとJTAG retryはいずれも0でした。

## Quartus結果

- Quartus Prime Lite 24.1std
- Logic elements: 23,477 / 28,848（81%）
- Worst setup slack: +6.776 ns
- Worst hold slack: +0.102 ns
- Full compilation: 0 errors

## ディレクトリ構成

```text
fpga/
├─ rtl/                              Verilog/SystemVerilog一式
├─ sim/                              シミュレーション・JTAG実行一式
├─ official/                         公式1000盤
├─ quartus/                          Quartusプロジェクト
├─ deliverables/                     提出用SOF
├─ minesweeper_fpga_result.xlsx      結果集計
├─ speed11_constraint8_simulation_1000.csv
├─ speed11_constraint8_hardware_1000.csv
└─ README.md
```

## シミュレーション

リポジトリのルートから実行します。

```powershell
.\fpga\sim\run_official_file.ps1 `
  -BoardFile .\fpga\official\board_pack_1000_fpga.txt `
  -ResultCsv fpga\speed11_constraint8_simulation_1000.csv `
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
  fpga/speed11_constraint8_hardware_1000.csv 1000 0 fast
```

## 提出物ハッシュ（SHA-256）

| ファイル | SHA-256 |
|---|---|
| SOF | `12D48A7DAF1442CEDA8647B20E0C0561532FD7D5BD8030D2B9C9895B04D62BCD` |
| Excel | `A63B0D398C820DF69BA2F09B692CE8749FC43C4C9B56EF136FC67F7900F8A373` |
