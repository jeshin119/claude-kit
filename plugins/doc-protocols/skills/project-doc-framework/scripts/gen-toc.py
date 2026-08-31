#!/usr/bin/env python3
"""<!-- TOC --> 자리에 h2/h3 목차를 생성한다. 이미 생성돼 있으면 갱신한다."""
import re, sys

MARK = "<!-- TOC -->"
END  = "<!-- /TOC -->"

def slug(text):
    s = text.strip().lower()
    s = re.sub(r'`', '', s)
    s = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', s)   # 링크는 라벨만
    s = re.sub(r'\*\*|__|\*|_', '', s)               # 강조 제거
    s = re.sub(r'[^\w\s-]', '', s, flags=re.UNICODE)
    return s.strip().replace(' ', '-')

def label(text):
    s = re.sub(r'`', '', text.strip())
    s = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', s)
    return re.sub(r'\*\*|__', '', s)

def build(md):
    out, fence = [], False
    for line in md.split('\n'):
        if line.lstrip().startswith('```'):
            fence = not fence
            continue
        if fence:
            continue
        m = re.match(r'^(#{2,3})\s+(.*\S)\s*$', line)
        if not m:
            continue
        depth, text = len(m.group(1)), m.group(2)
        indent = '  ' * (depth - 2)
        out.append(f'{indent}- [{label(text)}](#{slug(text)})')
    return '\n'.join(out)

for path in sys.argv[1:]:
    md = open(path, encoding='utf-8').read()
    body = re.sub(re.escape(MARK) + r'.*?' + re.escape(END), MARK, md, flags=re.S)
    if MARK not in body:
        print(f'skip (no marker): {path}'); continue
    toc = build(body.replace(MARK, ''))
    block = f'{MARK}\n{toc}\n{END}'
    assert body.count(MARK) == 1, path
    open(path, 'w', encoding='utf-8').write(body.replace(MARK, block))
    print(f'ok: {path} ({toc.count(chr(10))+1} 항목)')
