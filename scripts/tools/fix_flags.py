"""生成图里的旗画成了现实国家的国旗。策划案规定不指明国别，这里把旗面改成单色（室内瓶绿，地图赭黄）。
pixelize.py 重跑后要再跑一次这个。"""
from PIL import Image

FLAG = {(0x26, 0x35, 0x47), (0x4c, 0x66, 0x80), (0x93, 0xa9, 0xb4), (0xe6, 0xdc, 0xc3), (0xa8, 0x9d, 0x8a), (0xb8, 0x50, 0x3b), (0x7b, 0x2c, 0x25), (0x1c, 0x1b, 0x20)}
GREEN, MOSS = (0x3e, 0x5b, 0x3c), (0x6f, 0x8a, 0x4e)
OCHRE, LAMP = (0xc5, 0x8b, 0x3e), (0xec, 0xc1, 0x72)
JOBS = [
    ("assets/sprites/bg/town_map.png", (401, 64, 413, 78), OCHRE, LAMP),   # 地图上绿旗会融进草地
    ("assets/sprites/bg/loc_hall.png", (258, 48, 290, 160), GREEN, MOSS),
]
for path, (x0, y0, x1, y1), dark, bright in JOBS:
    im = Image.open(path).convert("RGB")
    px = im.load()
    for y in range(y0, y1):
        for x in range(x0, x1):
            c = px[x, y]
            if c in FLAG:
                light = c in {(0x93, 0xa9, 0xb4), (0xe6, 0xdc, 0xc3), (0xa8, 0x9d, 0x8a)}
                px[x, y] = bright if light else dark
    im.save(path)
    print("fixed", path)
