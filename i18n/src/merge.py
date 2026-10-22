import json,re,sys,glob
L=json.load(open('i18n/src/master_list.json'))
norm=lambda s:re.sub(r'\s+',' ',s).strip()
for lang in sys.argv[1:]:
    tr={}
    for f in sorted(glob.glob(f'i18n/src/{lang}*.tsv')):
        for line in open(f,encoding='utf-8'):
            line=line.rstrip('\n')
            if not line.strip(): continue
            i,t=line.split('\t',1); tr[int(i)]=t
    miss=[i for i in range(len(L)) if i not in tr]
    out={}; bad=[]
    for i,k in enumerate(L):
        if i not in tr: continue
        t=tr[i]
        ph=lambda s:sorted(re.findall(r'\{\d+\}|\{x\d*\}',s))
        tags=lambda s:sorted(re.findall(r'</?[a-z]+',s))
        if ph(k)!=ph(t) or tags(k)!=tags(t): bad.append((i,k,t))
        out[norm(k)]=norm(t)
    json.dump(out,open(f'i18n/{lang}.json','w'),ensure_ascii=False,separators=(',',':'))
    print(lang,'entries',len(out),'missing',len(miss),miss[:20],'bad',len(bad))
    for b in bad: print('  BAD',b)
