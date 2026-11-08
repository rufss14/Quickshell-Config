import re, sys
prop = re.compile(r'^\s*((?:[A-Za-z_]\w*\.)*[A-Za-z_]\w*)\s*:(?!:)')
def check(path):
    hits=[]
    stack=[{}]
    in_tpl = False          # inside a multi-line JS template literal (`…`): text, not QML
    for n,raw in enumerate(open(path), 1):
        ticks = len(re.findall(r'(?<!\\)`', raw))
        if in_tpl:
            if ticks % 2 == 1: in_tpl = False
            continue
        if ticks % 2 == 1:
            in_tpl = True
            raw = raw[:raw.index('`')]
        line = raw.split('//')[0]
        line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
        line = re.sub(r"'(?:[^'\\]|\\.)*'", "''", line)
        m = prop.match(line)
        if m and stack:
            name = m.group(1)
            if name not in ('function','property','readonly','signal','component','default','required'):
                if name in stack[-1]:
                    hits.append((n, name, stack[-1][name]))
                else:
                    stack[-1][name] = n
        for ch in line:
            if ch == '{': stack.append({})
            elif ch == '}':
                if len(stack) > 1: stack.pop()
    return hits
bad=0
# No arguments = every .qml in the repo (config/settings/ excepted). It used to check
# only what it was given, so the bare command CLAUDE.md documents checked NOTHING and
# still printed 0 (found 2026-10-04, when it let two Component.onDestruction through).
import os as _os
def _all_qml():
    root = _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__)))
    for d, dirs, fs in _os.walk(root):
        dirs[:] = [x for x in dirs if x != ".git" and not _os.path.join(d, x).endswith("config/settings")]
        for f in fs:
            if f.endswith(".qml"):
                yield _os.path.join(d, f)
for p in (sys.argv[1:] or sorted(_all_qml())):
    for n,name,first in check(p):
        print(f"{p}:{n}: '{name}' already set at line {first}")
        bad+=1
print(f"duplicates={bad}")
