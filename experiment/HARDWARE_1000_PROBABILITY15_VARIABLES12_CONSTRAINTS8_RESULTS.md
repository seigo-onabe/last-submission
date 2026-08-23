# 推論15回・12変数・8制約版 FPGA実機1000盤測定結果

## 概要

場合の数推論による確率選択を最大15回、列挙対象を最大12変数・8制約に設定し、
MU500実機で`board_pack_1000_fpga.txt`の全1000盤を実行した。

Quartusコンパイル、SOF書き込み、Virtual JTAG通信、1000盤の結果回収はすべて成功した。

## RTL設定

| 項目 | 設定値 |
|---|---:|
| `MAX_PROBABILITY_GUESSES` | 15 |
| `BASE_PROBABILITY_GUESSES` | 15 |
| `MAX_VARIABLES` | 12 |
| `MAX_COLLECTOR_CONSTRAINTS` | 8 |
| 半数未満継続 | 無効 |
| Adaptive feedback | 無効 |
| 低スコア時の辺中央救済 | 有効 |
| 救済安全セル閾値 | 16 |

通常の確率選択回数は`MAX_PROBABILITY_GUESSES`と`BASE_PROBABILITY_GUESSES`の
小さい方で制限されるため、両方を15に設定した。これにより実効上限が15回となる。

## 実行条件

| 項目 | 内容 |
|---|---|
| 実行環境 | MU500実機 |
| FPGA | Cyclone IV E `EP4CE30F23I7` |
| クロック | 20 MHz |
| 盤面数 | 1000盤 |
| 入力 | `experiment/official/board_pack_1000_fpga.txt` |
| 通信 | USB-Blaster / Virtual JTAG |
| JTAGモード | fast |

## 実機測定結果

| 指標 | 合計 | 1盤平均 | 最小 | 最大 |
|---|---:|---:|---:|---:|
| サイクル数 | 85,756,813 | 85,756.813 | 1,208 | 1,676,205 |
| スコア | 908.3174 | 0.9083174 | 0.0116 | 1.0000 |
| 開いた安全セル数 | 102,631 | 102.631 | 12 | 312 |
| 開いた地雷数 | 1,277 | 1.277 | 0 | 9 |

サイクル数の中央値は28,364.5サイクルだった。20 MHz動作時、合計85,756,813サイクルは
約4.288秒分のFPGA処理に相当する。

## 補足結果

| 項目 | 結果 |
|---|---:|
| 完全解答 | 891 / 1000盤 |
| 途中停止（stalled） | 109 / 1000盤 |
| 地雷を1つも開かなかった盤面 | 408盤 |
| JTAG再試行 | 0回 |
| JTAG転送エラー | 0件 |
| PING試験 | 5 / 5成功 |
| JTAG転送を含む実測時間 | 28.604秒 |

## FPGA素子使用量

Quartus Fitterの最終レポート値を示す。

| リソース | 使用量 | デバイス総量 | 使用率 |
|---|---:|---:|---:|
| Total logic elements | 22,910 | 28,848 | 79% |
| Total combinational functions | 21,677 | 28,848 | 75% |
| Dedicated logic registers | 8,464 | 28,848 | 29% |
| Total registers | 8,464 | ― | ― |
| Total memory bits | 38,943 bit | 608,256 bit | 6% |
| Embedded Multiplier 9-bit elements | 17 | 132 | 13% |
| I/O pins | 83 | 329 | 25% |
| PLL | 0 | 4 | 0% |

## タイミング結果

20 MHzクロックに対するSlow 1200 mV 100°Cモデルの主な結果を示す。

| 項目 | 最悪値 |
|---|---:|
| Setup slack | 6.898 ns |
| Hold slack | 0.341 ns |
| Recovery slack | 42.313 ns |

setup/hold slackはいずれも正であり、20 MHz動作のタイミングを満たしている。
Quartusフルコンパイルはエラー0件で完了した。

## 8回・12変数・8制約版との比較

| 指標 | 8回版 | 15回版 | 差（15回−8回） |
|---|---:|---:|---:|
| 合計サイクル数 | 76,802,797 | 85,756,813 | +8,954,016 |
| 平均サイクル数 | 76,802.797 | 85,756.813 | +8,954.016 |
| 平均スコア | 0.8929206 | 0.9083174 | +0.0153968 |
| 開いた安全セル合計 | 99,848 | 102,631 | +2,783 |
| 開いた地雷合計 | 1,214 | 1,277 | +63 |
| 完全解答数 | 858 | 891 | +33 |
| 途中停止数 | 142 | 109 | -33 |

推論回数を8回から15回へ増やすと平均スコアと完全解答数が向上した。一方で、
処理サイクル数と開いた地雷数も増加した。

## 成果物

- 設定トップ: `experiment/rtl/top/minesweeper_jtag_submission_local_top.v`
- 列挙パイプライン: `experiment/rtl/solver/solver_small_component_pipeline.v`
- 実機用SOF: `experiment/deliverables/minesweeper_probability15_variables12_constraints8_mu500.sof`
- 盤面別CSV: `experiment/hardware_1000_probability15_variables12_constraints8.csv`
- Quartusレポート: `experiment/quartus/reports_probability15_variables12_constraints8/`

## スコア

```text
スコア = 開いた安全セル数 / 全安全セル数
       - 開いた地雷数 / 全地雷数
```
