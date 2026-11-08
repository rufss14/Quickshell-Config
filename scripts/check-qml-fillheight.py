import re, sys
# Flag layouts nested directly inside a ColumnLayout-ish parent that never state
# Layout.fillHeight — Qt defaults it to TRUE for layout children, which silently
# steals surplus vertical space.
# SettingRow, SliderRow and Fader are not listed: each pins `Layout.fillHeight: false`
# on its own root, so no use of them can steal height.
LAYOUTS = ('ColumnLayout','RowLayout','GridLayout','Section','PanelHeader','SettingsPage','ChipRow')
def scan(path):
    src = open(path).read().split('\n')
    out=[]
    stack=[]   # (typename, line, depth)
    d=0
    for i,l in enumerate(src,1):
        s = re.sub(r'"[^"]*"','',l.split('//')[0])
        m = re.match(r'\s*([A-Z]\w*)\s*\{', l)
        opens = s.count('{'); closes = s.count('}')
        if m and opens:
            stack.append([m.group(1), i, d, False])
        d += opens - closes
        if re.search(r'Layout\.fillHeight\s*:', s) and stack:
            stack[-1][3] = True
        while stack and d <= stack[-1][2]:
            t,ln,dep,has = stack.pop()
            parent = stack[-1][0] if stack else None
            if t in LAYOUTS and parent == 'ColumnLayout' and not has:
                out.append((ln,t,parent))
    return out
for p in sys.argv[1:]:
    for ln,t,par in scan(p):
        print(f"{p}:{ln}: {t} inside {par} — no explicit Layout.fillHeight")
