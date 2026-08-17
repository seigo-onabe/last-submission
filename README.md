# ボマー — マインスイーパー提出物

開発者：長谷真暉・尾鍋正剛・井本有哉

このリポジトリには、マインスイーパーソルバーのソフトウェア版と、MU500
（Cyclone IV E `EP4CE30F23I7`）向けFPGA版を収録しています。

与えられた盤面の数字情報から、安全セルと地雷を可能な限り論理的に確定します。
論理だけで選択先を決められない局面では、数字制約を満たす地雷配置を数え、地雷を
選ぶ確率が低いセルを優先して開放します。ソフトウェア版はアルゴリズムの実装・評価用、
FPGA版は同じ課題をMU500実機で動作させるためのハードウェア実装です。

## 提出物の概要

### ソフトウェア版

ソフトウェア版はC++17で実装されています。基本的な数字制約、制約集合の部分集合関係、
盤面全体の残り地雷数を使って安全セル・地雷セルを確定します。確定できない場合には、
制約グラフを独立な成分に分けて有効な地雷配置を列挙し、各セルの地雷確率を計算します。
多数の盤面を処理するため、軽量な入力解析と最大2スレッドの並列処理を採用しています。

実装とアルゴリズムの詳細は [software/README.md](software/README.md) にまとめています。

### FPGA版

FPGA版はVerilog/SystemVerilogで記述し、Cyclone IV Eを搭載したMU500を対象にしています。
RTLには盤面読み込み、決定論的な制約伝播、確率に基づく選択、結果集計、7セグメント表示、
JTAG経由の盤面・結果転送を含みます。Quartusプロジェクト、シミュレーション用テストベンチ、
実機へ書き込むためのSOFファイルを同梱しています。

FPGA設計の方針、評価結果、シミュレーションおよびビルド方法は
[fpga/README.md](fpga/README.md) を参照してください。

## 構成

| 場所 | 内容 |
|---|---|
| `software/minesweeper_solver.cpp` | C++17によるソフトウェア版ソルバー |
| `software/board_pack_10000_prog.txt` | ソフトウェア版の入力盤面 |
| `software/minesweeper_prog_result.xlsx` | ソフトウェア版の結果 |
| `fpga/` | Verilog RTL、シミュレーション、Quartusプロジェクト、FPGA成果物 |
| `fpga/deliverables/minesweeper_submission_local_mu500.sof` | MU500へ書き込むコンフィギュレーションファイル |
| `fpga/minesweeper_fpga_result.xlsx` | FPGA版の結果 |

## READMEの案内

| ファイル | 内容 |
|---|---|
| [software/README.md](software/README.md) | ソフトウェア版の実装内容、アルゴリズム、使用技術 |
| [fpga/README.md](fpga/README.md) | FPGA版の設計方針、評価結果、実行・ビルド・実機試験手順 |
