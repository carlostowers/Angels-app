import re,sys
# uso: merge_feed.py salida.html final.html snap_mas_nuevo.html snap_mas_viejo.html ...
def items(path):
    h=open(path,encoding='utf-8').read()
    a=h.index('<h2>Play-by-Play</h2>')+len('<h2>Play-by-Play</h2>')
    b=h.index('<div class="bz-actions">',a)
    body=h[a:b]
    out=[]; cur=None
    for m in re.finditer(r'<div class="bz-inning-hd">([^<]*)</div>|(<div class="bz-feed-item">.*?<div class="bz-feed-side">\s*([^<]*?)\s*</div>\s*</div>)', body, re.S):
        if m.group(1) is not None: cur=m.group(1).strip(); continue
        blk=m.group(2); st=re.search(r'<strong>(.*?)</strong>',blk).group(1); sc=m.group(3).strip()
        nm=re.search(r'<span>(.*?)</span>',blk,re.S); nm=re.sub(r'<[^>]+>','',nm.group(1)).strip() if nm else ''
        out.append(((cur,st,sc,nm),blk))
    return h,a,b,out
h,a,b,F=items(sys.argv[2])
merged=list(F)
for p in sys.argv[3:]:
    _,_,_,S=items(p)
    keys=[k for k,_ in S]; mk=[k for k,_ in merged]
    best=(0,None)
    for m in range(min(len(mk),len(keys)),5,-1):
        tail=mk[-m:]
        for k in range(0,len(keys)-m+1):
            if keys[k:k+m]==tail: best=(m,k); break
        if best[1] is not None: break
    if best[1] is None: print('sin solape con',p); continue
    m,k=best; add=S[k+m:]; merged+=add
    print(p,'solape',m,'agrega',len(add))
html=''; cur=None
for (st,_,_,_),blk in merged:
    if st!=cur: html+='\n                  <div class="bz-inning-hd">%s</div>\n                  '%st; cur=st
    html+=blk+'\n                  '
c=h.index('</div>',h.rindex('<div class="bz-feed-item">',a,b))  # not used
new=h[:a]+html+'\n              </div>\n            </div>\n          </div>\n\n        \n\n        '+h[b:]
open(sys.argv[1],'w',encoding='utf-8').write(new)
print('total items',len(merged), 'sets', sorted(set(k[0] for k,_ in merged)))
