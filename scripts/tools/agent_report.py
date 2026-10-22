"""子 Agent 试玩汇总：读会话目录里的 notes.md，数无聊度、困惑、像程序写的句子；再用 replay_report 重放存档。
用法：python -I scripts/tools/agent_report.py <会话目录>... [--out 汇总.md]
"""
import os, re, subprocess, sys

GODOT = "E:/Godot/Godot_v4.7.2-stable_win64_console.exe"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def notes_stats(path):
    rows = []
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\s*\[(第\d+周[^\]]*)\](.*)", line)
        if not m:
            continue
        b = re.search(r"无聊度\s*[:：]?\s*(\d)", line)
        rows.append({"when": m.group(1), "bored": int(b.group(1)) if b else None,
                     "confused": "困惑" in line, "robot": re.findall(r"像程序写的[:：]\s*「([^」]+)」", line),
                     "good": re.findall(r"好句[:：]\s*「([^」]+)」", line), "line": line.strip()})
    return rows


def main():
    args = sys.argv[1:]
    out = None
    if "--out" in args:
        i = args.index("--out")
        out = args[i + 1]
        args = args[:i] + args[i + 2:]
    lines = []
    for d in args:
        name = os.path.basename(d.rstrip("/\\"))
        rows = notes_stats(os.path.join(d, "notes.md")) if os.path.exists(os.path.join(d, "notes.md")) else []
        scored = [r for r in rows if r["bored"] is not None]
        lines.append(f"## {name}\n")
        lines.append(f"- 记录 {len(rows)} 条；平均无聊度 {sum(r['bored'] for r in scored) / max(1, len(scored)):.2f}；"
                     f"无聊度≥2 的 {sum(1 for r in scored if r['bored'] >= 2)} 条，=3 的 {sum(1 for r in scored if r['bored'] == 3)} 条；困惑 {sum(1 for r in rows if r['confused'])} 条")
        by_week = {}
        for r in scored:
            w = re.match(r"第(\d+)周", r["when"]).group(1)
            by_week.setdefault(w, []).append(r["bored"])
        lines.append("- 每周平均无聊度：" + "，".join(f"第{w}周 {sum(v) / len(v):.1f}" for w, v in sorted(by_week.items())))
        robots = [s for r in rows for s in r["robot"]]
        goods = [s for r in rows for s in r["good"]]
        if robots:
            lines.append("- 像程序写的：\n" + "\n".join(f"  - 「{s}」" for s in robots))
        if goods:
            lines.append("- 好句：\n" + "\n".join(f"  - 「{s}」" for s in goods))
        save = os.path.join(d, "save.json")
        if os.path.exists(save):
            rep = os.path.join(d, "replay.md")
            subprocess.run([GODOT, "--headless", "--path", ROOT, "-s", "res://scripts/tools/replay_report.gd", "--", "--save", save, "--out", rep],
                           capture_output=True)
            lines.append(f"- 重放：{rep}")
        lines.append("")
    text = "\n".join(lines)
    if out:
        open(out, "w", encoding="utf-8").write(text)
    sys.stdout.reconfigure(encoding="utf-8")
    print(text)


main()
