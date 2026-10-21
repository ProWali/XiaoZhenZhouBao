"""把生成的草图压成游戏用的像素底图：缩到目标尺寸，压进 16 色调色板。
用法：python scripts/tools/pixelize.py 源图 输出 [宽 高] [--dither]
调色板和 scripts/ui/palette.gd 是同一套，改一边要改另一边。"""
import sys

import numpy as np
from PIL import Image

PALETTE = [
    "1c1b20", "3b3536", "6e6459", "a89d8a", "e6dcc3",  # 墨、焦褐、暖灰、石色、纸
    "4e3320", "87562e", "c58b3e", "ecc172",            # 深褐、褐、赭、灯黄
    "7b2c25", "b8503b",                                # 深砖红、砖红
    "263547", "4c6680", "93a9b4",                      # 深石板蓝、石板蓝、浅石板
    "3e5b3c", "6f8a4e",                                # 瓶绿、苔绿
]
PAL = np.array([[int(h[i:i + 2], 16) for i in (0, 2, 4)] for h in PALETTE], dtype=np.float32)


def to_lab(rgb: np.ndarray) -> np.ndarray:
    c = rgb / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.9505, 1.0, 1.089])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


PAL_LAB = to_lab(PAL)
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16 - 0.47


def quantize(img: Image.Image, dither: bool) -> Image.Image:
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    if dither:
        h, w = a.shape[:2]
        a = a + np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w, None] * 18
    lab = to_lab(np.clip(a, 0, 255))
    d = ((lab[:, :, None, :] - PAL_LAB[None, None]) ** 2).sum(-1)
    idx = d.argmin(-1)
    return Image.fromarray(PAL[idx].astype(np.uint8))


def main() -> None:
    args = [x for x in sys.argv[1:] if not x.startswith("--")]
    src, dst = args[0], args[1]
    w, h = (int(args[2]), int(args[3])) if len(args) >= 4 else (640, 360)
    img = Image.open(src).convert("RGBA")
    alpha = img.getchannel("A")
    small = img.convert("RGB").resize((w, h), Image.Resampling.LANCZOS)
    out = quantize(small, "--dither" in sys.argv)
    if alpha.getextrema()[0] < 255:
        a = alpha.resize((w, h), Image.Resampling.BOX).point(lambda v: 255 if v > 128 else 0)
        out = out.convert("RGBA")
        out.putalpha(a)
    out.save(dst)
    print(dst, out.size)


if __name__ == "__main__":
    main()
