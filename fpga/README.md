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

Quartus Prime Lite 24.1std エディションを使用しています。

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

## 本番デモ表示

7セグは4行×16桁を次の固定レイアウトで使用します。英字は7セグ向けの
近似字体です。

```text
boArd 1000 donE
FULL0862PArt0138
 CYCLE  81110615
 SCORE  0903.8487
```

- `boArd`: 処理済み盤面数と `UAIt` / `run` / `donE` / `Err`
- `FULL`: 全安全セルを開けた盤面数
- `PArt`: 完全解答に至らなかった盤面数（`boArd - FULL`）
- `CYCLE`: 累計ソルバーサイクル（8桁超過時は `--------`）
- `SCORE`: 累計スコア（小数4桁）

通常LEDは、待機中は中央のHeartbeat、実行中は64段階の蛇行プログレス、
完了時は外周・内側・全灯の順で演出します。エラー時はチェッカーボードを
交互点滅します。

JTAGプロトコルv3では、ランナーが実行前に総盤面数を通知し、最終結果の
ACK後にバッチ終了を通知します。これにより、1盤・1000盤のどちらでも
同じSOFで正確な進捗と完了演出を行えます。
