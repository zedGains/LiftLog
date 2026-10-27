"""Copy the rank emblem drawing code from index.html into api/_emblem.js,
so invite link previews draw the same crests and helms as the app.
Run from the repo root after changing rank emblems: python3 tools/build_emblem.py"""
import re
s = open('index.html').read()
def fn(name):
    a = s.index('function ' + name + '(')
    m = re.search(r'\n(function |const |let |/\*)', s[a + 10:])
    return s[a:a + 10 + m.start()] + '\n'
def line(prefix):
    a = s.index(prefix); b = s.index('\n', a); return s[a:b] + '\n'
src = line('const RANKS=[') + fn('rankInfo') + fn('crestBlades') + 'let rfN=0;\n' + fn('rankFrame') + line('const HPLUME=') + 'let hmN=0;\n' + fn('helmEmblem') + fn('initialsOf')
src = src.replace("style=\"font-family:'Barlow Condensed','Arial Narrow',Arial,sans-serif\"", '')
hdr = '''// Generated from index.html by tools/build_emblem.py — don't edit by hand.
const esc=(t)=>String(t).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
'''
open('api/_emblem.js', 'w').write(hdr + src + '\nexport {RANKS,rankInfo,rankFrame,helmEmblem,initialsOf,esc};\n')
