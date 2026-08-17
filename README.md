# ボマー — マインスイーパー提出物

開発者：長谷真暉・尾鍋正剛・井本有哉

このリポジトリには、マインスイーパーソルバーのソフトウェア版と、MU500
（Cyclone IV E `EP4CE30F23I7`）向けFPGA版を収録しています。

## 構成

| 場所 | 内容 |
|---|---|
| `software/minesweeper_solver.cpp` | C++17によるソフトウェア版ソルバー |
| `software/board_pack_10000_prog.txt` | ソフトウェア版の入力盤面 |
| `software/minesweeper_prog_result.xlsx` | ソフトウェア版の結果 |
| `fpga/` | Verilog RTL、シミュレーション、Quartusプロジェクト、FPGA成果物 |
| `fpga/deliverables/minesweeper_submission_local_mu500.sof` | MU500へ書き込むコンフィギュレーションファイル |
| `fpga/minesweeper_fpga_result.xlsx` | FPGA版の結果 |

FPGA版の設計、評価結果、シミュレーションおよびビルド方法は
[fpga/README.md](fpga/README.md) を参照してください。
