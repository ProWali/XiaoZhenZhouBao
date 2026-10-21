"""Steam 商店页素材：从像素底图整数倍放大后裁切，叠标题。输出到 design/steam/。
尺寸按策划案十一版（Steam 2026 年的规格）。"""
from PIL import Image, ImageDraw, ImageFont

BG = "assets/sprites/bg/"
OUT = "design/steam/"
FONT = "assets/fonts/serif-black-sub.otf"
FONT_R = "assets/fonts/serif-sub.otf"
PAPER, LAMP, INK = (230, 220, 195), (236, 193, 114), (28, 27, 32)
TITLE, SUB = "小镇周报", "灰河镇 · 一九三五"


def up(path, k):
    im = Image.open(BG + path).convert("RGB")
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def fit(im, w, h, cx=0.5, cy=0.5):
    """按目标比例裁切再缩放（先整数倍放大过，缩放后仍保留像素感）"""
    r = w / h
    if im.width / im.height > r:
        nw = int(im.height * r)
        x0 = int((im.width - nw) * cx)
        im = im.crop((x0, 0, x0 + nw, im.height))
    else:
        nh = int(im.width / r)
        y0 = int((im.height - nh) * cy)
        im = im.crop((0, y0, im.width, y0 + nh))
    return im.resize((w, h), Image.LANCZOS)


def shade(im, box, alpha=150):
    """box 范围内压暗，朝右（竖图朝下）渐隐，不留硬边"""
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    x0, y0, x1, y1 = box
    vertical = (x1 - x0) >= im.width and (y1 - y0) < im.height
    span = (y1 - y0) if vertical else (x1 - x0)
    for i in range(span):
        a = int(alpha * min(1.0, 1.6 * (1 - i / span)))
        if vertical:
            d.line([(x0, y0 + i), (x1, y0 + i)], fill=INK + (a,))
        else:
            d.line([(x0 + i, y0), (x0 + i, y1)], fill=INK + (a,))
    return Image.alpha_composite(im.convert("RGBA"), ov).convert("RGB")


def title(im, x, y, size, sub=True, anchor="la"):
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(FONT, size)
    d.text((x + max(1, size // 24), y + max(1, size // 24)), TITLE, font=f, fill=INK, anchor=anchor)
    d.text((x, y), TITLE, font=f, fill=PAPER, anchor=anchor)
    if sub:
        fs = ImageFont.truetype(FONT_R, max(10, size // 3))
        sy = y + int(size * 1.15)
        d.text((x + 2, sy), SUB, font=fs, fill=LAMP, anchor=anchor)
    return im


def main():
    town = up("menu_town.png", 4)
    office = up("office.png", 4)
    # 主胶囊 616×353、大胶囊 1232×706、头图 460×215、小胶囊 231×87
    for name, (w, h), size in [("main_capsule", (616, 353), 72), ("large_capsule", (1232, 706), 144), ("header_capsule", (460, 215), 54)]:
        im = fit(town, w, h, 0.55, 0.5)
        im = shade(im, (0, 0, int(w * 0.56), h), 70)
        title(im, int(w * 0.06), int(h * 0.12), size)
        im.save(OUT + name + ".png")
    im = fit(town, 231, 87, 0.6, 0.5)
    im = shade(im, (0, 0, 231, 87), 90)
    title(im, 115, 44, 40, sub=False, anchor="mm")
    im.save(OUT + "small_capsule.png")
    # 库封面 600×900：编辑室的桌子和台灯
    im = fit(office, 600, 900, 0.5, 0.5)
    im = shade(im, (0, 0, 600, 230), 120)
    title(im, 300, 70, 96, sub=False, anchor="mt")
    d = ImageDraw.Draw(im)
    d.text((300, 190), SUB, font=ImageFont.truetype(FONT_R, 30), fill=LAMP, anchor="mt")
    im.save(OUT + "library_capsule.png")
    # 库主图 3840×1240：没有字
    fit(town, 3840, 1240, 0.5, 0.55).save(OUT + "library_hero.png")
    # 透明 Logo
    logo = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
    d = ImageDraw.Draw(logo)
    f = ImageFont.truetype(FONT, 260)
    d.text((646, 366), TITLE, font=f, fill=INK + (255,), anchor="mm")
    d.text((640, 360), TITLE, font=f, fill=PAPER + (255,), anchor="mm")
    logo.crop(logo.getbbox()).save(OUT + "logo.png")
    print("done")


if __name__ == "__main__":
    main()
