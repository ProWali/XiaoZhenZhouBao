"""把正文字体裁成游戏用得到的字：GB2312 全部汉字 + 项目里出现过的所有字符 + 拉丁字母。
用法：python scripts/tools/subset_fonts.py <源字体目录>
源字体目录里要有 wenkai.ttf（霞鹜文楷 Regular）、serif-r.otf、serif-b.otf（思源宋体 SC Regular / Black）。
加了新界面文字后重跑一次，保证新字在字体里。"""
import pathlib
import sys

from fontTools import subset

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = pathlib.Path(sys.argv[1])
OUT = ROOT / "assets" / "fonts"


def charset() -> str:
    chars = set()
    for hi in range(0xB0, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                chars.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    for c in range(0x20, 0x7F):
        chars.add(chr(c))
    chars.update("“”‘’—…·「」『』《》〈〉、。，；：？！（）【】〔〕　①②③④⑤×÷±°℃¥€£éèêëàâçîïôöûüñÉ")
    for pat in ("data/**/*.json", "scripts/**/*.gd", "scenes/**/*.tscn"):
        for p in ROOT.glob(pat):
            chars.update(p.read_text(encoding="utf-8"))
    return "".join(sorted(c for c in chars if c.isprintable() or c == "　"))


def run(src: str, dst: str, text: str) -> None:
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    font = subset.load_font(str(SRC / src), opts)
    sub = subset.Subsetter(opts)
    sub.populate(text=text)
    sub.subset(font)
    subset.save_font(font, str(OUT / dst), opts)
    print(dst, (OUT / dst).stat().st_size // 1024, "KB")


if __name__ == "__main__":
    text = charset()
    print(len(text), "chars")
    run("wenkai.ttf", "wenkai-sub.ttf", text)
    run("serif-r.otf", "serif-sub.otf", text)
    run("serif-b.otf", "serif-black-sub.otf", text)
