# -*- coding: utf-8 -*-
"""盲测防污染检查：生成器的中文模板里，不能出现和任何一轮手写稿雷同的片段。

    python -I scripts/tools/check_contamination.py

规则：去掉人名、槽位和语法符号后，连续 7 个汉字与某篇手写稿相同就算雷同。
手写稿来源：design/blind/archive/ 下的历轮存档（.json 或 .txt），以及当前的 design/blind/handwritten_zh.json。
白名单：design/blind/archive/allowed.txt，每行一个片段。只放「早于手写稿就存在于模拟层事实原文里的说法」，并写明理由。
有雷同时退出码为 1，盲测工具出卷前必须先跑通它。
"""
import io, json, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
N = 7


def han(s):
    s = re.sub(r'[一-鿿]+·[一-鿿]+', '', s)  # 人名
    s = re.sub(r'\{[^}]*\}|#[^#]*#', '', s)                   # 槽位、语法符号
    return ''.join(ch for ch in s if '一' <= ch <= '鿿')


def hand_texts():
    out = []
    arch = os.path.join(ROOT, 'design', 'blind', 'archive')
    files = [os.path.join(arch, f) for f in sorted(os.listdir(arch))] if os.path.isdir(arch) else []
    files.append(os.path.join(ROOT, 'design', 'blind', 'handwritten_zh.json'))
    for p in files:
        if p.endswith('allowed.txt') or not os.path.exists(p):
            continue
        if p.endswith('.json'):
            for v in json.loads(io.open(p, encoding='utf-8').read()).values():
                out.append((os.path.basename(p), v['headline'] + '。' + ''.join(v['body'])))
        elif p.endswith('.txt'):
            for line in io.open(p, encoding='utf-8').read().splitlines():
                if line.strip():
                    out.append((os.path.basename(p), line))
    return out


def allowed():
    p = os.path.join(ROOT, 'design', 'blind', 'archive', 'allowed.txt')
    if not os.path.exists(p):
        return set()
    return {han(l.split('#')[0]) for l in io.open(p, encoding='utf-8').read().splitlines() if han(l.split('#')[0])}


def main():
    grams = {}
    for src, t in hand_texts():
        h = han(t)
        for i in range(len(h) - N + 1):
            grams.setdefault(h[i:i + N], src)
    ok_frags = allowed()
    hits = []

    def walk(obj, path):
        if isinstance(obj, str):
            h = han(obj)
            found = set()
            for i in range(len(h) - N + 1):
                gram = h[i:i + N]
                if gram in grams and not any(gram in a for a in ok_frags):
                    found.add((gram, grams[gram]))
            if found:
                hits.append((path, obj, sorted(found)))
        elif isinstance(obj, dict):
            for k, v in obj.items():
                walk(v, path + '.' + str(k))
        elif isinstance(obj, list):
            for i, v in enumerate(obj):
                walk(v, path + '[%d]' % i)

    for f in ['events', 'grammar', 'letters', 'visitors', 'ui']:
        p = os.path.join(ROOT, 'data', 'text', 'zh', f + '.json')
        walk(json.loads(io.open(p, encoding='utf-8').read()), f)
    report = os.path.join(ROOT, 'design', 'blind', 'contamination_report.txt')
    with io.open(report, 'w', encoding='utf-8', newline='\n') as out:
        for path, text, found in hits:
            out.write('%s | %s | %s\n' % (path, text, ' / '.join('%s（%s）' % g for g in found)))
    print('contamination hits: %d (report: design/blind/contamination_report.txt)' % len(hits))
    return 1 if hits else 0


if __name__ == '__main__':
    sys.exit(main())
