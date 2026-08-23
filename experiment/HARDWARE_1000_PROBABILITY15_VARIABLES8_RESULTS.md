# 推論15回・場合の数8変数版 FPGA実機1000盤測定結果

## 概要

確率選択の上限を15回、場合の数推論で列挙する最大変数数を8に設定したRTLを
Quartus Prime Lite 24.1stdで再コンパイルし、MU500実機上で
`board_pack_1000_fpga.txt`の全1000盤を実行した。

SOF生成、実機書き込み、Virtual JTAG通信、1000盤の結果回収はすべて正常に完了した。

## RTL設定

| 項目 | 設定値 |
|---|---:|
| 確率選択上限 `MAX_PROBABILITY_GUESSES` | 15回 |
| 基準回数 `BASE_PROBABILITY_GUESSES` | 8回 |
| 場合の数推論の最大変数数 `MAX_VARIABLES` | 8変数 |
| 半数未満継続 | 無効 |
| Adaptive feedback | 無効 |
| 低スコア時の辺中央救済 | 有効 |
| 救済安全セル閾値 | 16 |

`MAX_VARIABLES=8`は、成分構築器、配置列挙器、強制セル抽出器に同じ値を伝播させている。
8変数を超える成分はこの小規模列挙器では処理せず、他の制約推論または別候補へ進む。

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
| サイクル数 | 65,017,199 | 65,017.199 | 1,208 | 695,640 |
| スコア | 860.2292 | 0.8602292 | -0.0235 | 1.0000 |
| 開いた安全セル数 | 96,202 | 96.202 | 10 | 312 |
| 開いた地雷数 | 1,226 | 1.226 | 0 | 8 |

サイクル数の中央値は28,131.5サイクルだった。20 MHz動作時、合計65,017,199サイクルは
約3.251秒分のFPGA処理に相当する。

## 補足結果

| 項目 | 結果 |
|---|---:|
| 完全解答 | 789 / 1000盤 |
| 途中停止（stalled） | 211 / 1000盤 |
| 地雷を1つも開かなかった盤面 | 413盤 |
| JTAG再試行 | 0回 |
| JTAG転送エラー | 0件 |
| PING試験 | 5 / 5成功 |
| JTAG転送を含む実測時間 | 27.562秒 |

## FPGA素子使用量

Quartus Fitterの最終レポート値を示す。

| リソース | 使用量 | デバイス総量 | 使用率 |
|---|---:|---:|---:|
| Total logic elements | 22,125 | 28,848 | 77% |
| Total combinational functions | 20,870 | 28,848 | 72% |
| Dedicated logic registers | 8,200 | 28,848 | 28% |
| Total registers | 8,200 | ― | ― |
| Total memory bits | 38,943 bit | 608,256 bit | 6% |
| Embedded Multiplier 9-bit elements | 17 | 132 | 13% |
| I/O pins | 83 | 329 | 25% |
| PLL | 0 | 4 | 0% |

### 12変数版ビルドとの素子数比較

リポジトリに同梱されていた12変数版のQuartus Fitter結果と比較する。

| リソース | 12変数版 | 8変数版 | 差 |
|---|---:|---:|---:|
| Total logic elements | 23,477 | 22,125 | -1,352 |
| Combinational functions | 22,192 | 20,870 | -1,322 |
| Dedicated logic registers | 8,600 | 8,200 | -400 |
| Memory bits | 38,943 | 38,943 | 0 |
| 9-bit multiplier elements | 17 | 17 | 0 |

場合の数推論を12変数から8変数へ縮小したことで、論理素子は1,352個、約5.76%減少した。
メモリビット数と乗算器数は変化しなかった。

## タイミング結果

20 MHzクロックに対するQuartus Timing Analyzerの主な結果は次の通りである。

| 項目 | 最悪値 |
|---|---:|
| Setup slack | 6.980 ns |
| Hold slack | 0.395 ns |
| Recovery slack | 42.577 ns |
| Removal slack | 1.167 ns |

setup/hold slackはいずれも正であり、20 MHzの指定タイミングを満たしている。
Quartusフルコンパイルはエラー0件で完了した。

## 8回・12変数版との実機結果比較

直前に測定した「確率選択8回・最大12変数」の結果と比較する。ただし、確率選択回数と
変数数の両方が異なるため、差をどちらか一方の効果として分離することはできない。

| 指標 | 8回・12変数 | 15回・8変数 | 差 |
|---|---:|---:|---:|
| 合計サイクル数 | 76,802,797 | 65,017,199 | -11,785,598 |
| 平均スコア | 0.8929206 | 0.8602292 | -0.0326914 |
| 開いた安全セル合計 | 99,848 | 96,202 | -3,646 |
| 開いた地雷合計 | 1,214 | 1,226 | +12 |
| 完全解答数 | 858 | 789 | -69 |
| 途中停止数 | 142 | 211 | +69 |

## 成果物

- 8変数版RTL: `experiment/rtl/solver/solver_small_component_pipeline.v`
- 15回設定トップ: `experiment/rtl/top/minesweeper_jtag_submission_local_top.v`
- 実機用SOF: `experiment/deliverables/minesweeper_probability15_variables8_mu500.sof`
- 盤面別結果: `experiment/hardware_1000_probability15_variables8.csv`
- Quartus素子・タイミングレポート: `experiment/quartus/reports_probability15_variables8/`

## スコア

各盤面のスコアは次の評価式に相当し、小数点以下4桁の固定小数としてFPGA内で計算される。

```text
スコア = 開いた安全セル数 / 全安全セル数
       - 開いた地雷数 / 全地雷数
```
