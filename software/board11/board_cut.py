# board_pack_10000_prog.txt を 11 ファイルに，およそ 12400 行ごとに切り分ける
# 実行の際，本体のコードは 2000 行を超えてはならない

import sys

input_file = sys.argv[1]

target_lines = 12400
num_files = 11

with open(input_file, "r", encoding="utf-8") as f:
    lines = f.readlines()

start = 0

for i in range(num_files):
    if i == num_files - 1:
        end = len(lines)
    else:
        end = start + target_lines

        # target_lines 行以内で、直前にある空行を探す
        while end > start and lines[end - 1].strip() != "":
            end -= 1

    filename = f"board{i+1:02d}.txt"

    with open(filename, "w", encoding="utf-8") as f:
        f.writelines(lines[start:end])

    print(f"{filename}: {end - start} lines")
    start = end