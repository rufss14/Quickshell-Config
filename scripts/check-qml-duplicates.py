import re, sys
# A statement that sets a property: `name:` / `a.b.name:` / `Attached.onX:`, or a DECLARATION with a value
# (`property color accent: …`), which sets it just the same: declared with a value and then assigned
# (PrivacyPill's `accent`) is "Property value set multiple times" too.
prop = re.compile(r'\s*(?:((?:[A-Za-z_]\w*\.)*[A-Za-z_]\w*)\s*:(?!:)'
                  r'|(?:(?:readonly|required|default)\s+)*property\s+[\w<>.]+\s+([A-Za-z_]\w*)\s*:(?!:))')
SKIP = ('function','property','readonly','signal','component','default','required','case','return')
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
        # Every statement on the line, not just the first: `Row { x: 1; y: 2; x: 3 }` is one line.
        # A statement starts at the line's start and after each `{`, `}` or `;` outside parentheses
        # (a `for (;;)` header and a call's object-literal argument are not statement starts).
        at_start, paren = True, 0
        for i, ch in enumerate(line):
            if at_start and not ch.isspace():
                m = prop.match(line, i)
                if m and stack:
                    name = m.group(1) or m.group(2)
                    if name not in SKIP:
                        if name in stack[-1]:
                            hits.append((n, name, stack[-1][name]))
                        else:
                            stack[-1][name] = n
                at_start = False
            if ch in '([': paren += 1
            elif ch in ')]': paren = max(0, paren - 1)
            elif ch == '{':
                stack.append({}); at_start = paren == 0
            elif ch == '}':
                if len(stack) > 1: stack.pop()
                at_start = paren == 0
            elif ch == ';' and paren == 0:
                at_start = True
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
