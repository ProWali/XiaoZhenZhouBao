"""编辑室底图是夜里画的。白天用的变体：把窗玻璃和门上小窗里的夜色换成白天的天光。屋里不动（试过棋盘格提亮，太脏）。
pixelize.py 重跑 office 后要再跑一次这个。"""
from PIL import Image

H = lambda s: tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))
NIGHT_TO_DAY = {
    H("1c1b20"): H("6e6459"), H("263547"): H("93a9b4"), H("4c6680"): H("e6dcc3"),
    H("3b3536"): H("a89d8a"), H("ecc172"): H("e6dcc3"), H("c58b3e"): H("a89d8a"), H("87562e"): H("6e6459"),
    H("93a9b4"): H("e6dcc3"),
}
GLASS = [(22, 14, 78, 222), (570, 40, 604, 100)]   # 左窗、门上小窗

im = Image.open("assets/sprites/bg/office.png").convert("RGB")
px = im.load()
w, h = im.size
for y in range(h):
    for x in range(w):
        in_glass = any(x0 <= x < x1 and y0 <= y < y1 for x0, y0, x1, y1 in GLASS)
        c = px[x, y]
        if in_glass and c in NIGHT_TO_DAY:
            px[x, y] = NIGHT_TO_DAY[c]
im.save("assets/sprites/bg/office_day.png")
print("office_day.png")
