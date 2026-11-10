"""Writes a pretend Tesseract TSV "screen" for the Show Me How tests (Job 22).

Usage: python3 tests/showme-make.py OUT WIDTH HEIGHT "Add Printer@100,200" "Pay@40,50,10" ...
Each item = one line of words at x,y (pixels); a third number is Tesseract's sureness (default 95).
Every word is 9 pixels per letter wide and 16 high, with 8 pixels between words.
"""
import sys

out, width, height = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
rows = ["level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext",
        "1\t1\t0\t0\t0\t0\t0\t0\t%d\t%d\t-1\t" % (width, height)]
for block, item in enumerate(sys.argv[4:], 1):
    text, _, where = item.rpartition("@")
    nums = [int(n) for n in where.split(",")]
    x, y, conf = nums[0], nums[1], (nums[2] if len(nums) > 2 else 95)
    rows.append("4\t1\t%d\t1\t1\t0\t%d\t%d\t100\t16\t-1\t" % (block, x, y))
    for n, word in enumerate(text.split(), 1):
        rows.append("5\t1\t%d\t1\t1\t%d\t%d\t%d\t%d\t16\t%d\t%s" % (block, n, x, y, 9 * len(word), conf, word))
        x += 9 * len(word) + 8
with open(out, "w", encoding="utf-8") as f:
    f.write("\n".join(rows) + "\n")
