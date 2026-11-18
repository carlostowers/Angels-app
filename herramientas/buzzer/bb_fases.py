#!/usr/bin/env python3
# Fases de juego desde el jugada a jugada oficial (buzzerbeaterpr.com):
# K1 (side-out: recepcion -> primer ataque), FBSO (first ball side-out),
# K2 (contraataque del equipo que saca) y transicion del que recibe.
# El sitio publica solo los ultimos 200 toques de cada partido: se calcula
# con los rallies completos que entran en esa ventana y se reporta el n.
# Uso: python3 -I bb_fases.py <carpeta_html> <datos.json>
# Agrega a cada partido del JSON la llave "fases" (lo lee la pagina Buzzer).
import re, sys, os, json, html, glob

RAW, BB = sys.argv[1], sys.argv[2]
LISTA = json.load(open(BB))
partidos = {m['id']: m for m in LISTA}


def txt(s):
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', s))).strip()


def nuevo():
    return {'rec': 0, 'fbk': 0, 'so': 0, 'k1': [0, 0, 0, 0], 'k2': [0, 0, 0, 0], 'tr': [0, 0, 0, 0],
            'sin_ataque': 0, 'bp_n': 0, 'bp_w': 0, 'k2_ral': 0, 'k2_pts': 0}


def suma(a, b):
    for k, v in b.items():
        if isinstance(v, list):
            a[k] = [x + y for x, y in zip(a.get(k, [0] * len(v)), v)]
        else:
            a[k] = a.get(k, 0) + v


res = {}
for f in sorted(glob.glob(os.path.join(RAW, 'm_*.html'))):
    gid = re.search(r'-(g\d+-\d+)\.html$', f).group(1)
    m = partidos.get(gid)
    if not m or m['status'] == 'pendiente' or not m['home'] or not m['away']:
        continue
    h = open(f, encoding='utf-8').read()
    home, away = m['home'], m['away']
    who = {}
    for side in ('h', 'a'):
        for r in m['box'][side]:
            if r.get('pid'):
                who[r['pid']] = (side, r['num'])
    feed = h[h.find('<h2>Play-by-Play</h2>'):]
    feed = feed[:feed.find('class="bz-actions"')] if 'class="bz-actions"' in feed else feed
    ev = []
    cur = 0
    for part in re.split(r'(?=<div class="bz-inning-hd">)|(?=<div class="bz-feed-item">)', feed):
        if part.startswith('<div class="bz-inning-hd">'):
            cur = int(re.search(r'Set (\d+)', part).group(1))
            continue
        if not part.startswith('<div class="bz-feed-item">'):
            continue
        st = re.search(r'<strong>(.*?)</strong>', part, re.S)
        sc = re.search(r'bz-feed-side">\s*(\d+)-(\d+)', part)
        if not st or not sc:
            continue
        x = txt(st.group(1))
        link = re.search(r'volleyball-leaders/[a-z0-9-]*-(\d+)"', part)
        team = None
        num = None
        if link and link.group(1) in who:
            team, num = who[link.group(1)]
        else:
            mm = re.match(r'^(.+?)\s*(?:·\s*)?(?:#(\d+)\s|point|fault)', x)
            if mm:
                pre = mm.group(1).strip(' ·')
                if pre and (home.startswith(pre) or pre.startswith(home.split(' -')[0]) or pre == home):
                    team = 'h'
                elif pre and (away.startswith(pre) or pre.startswith(away.split(' -')[0]) or pre == away):
                    team = 'a'
                num = mm.group(2)
        mn = re.search(r'#(\d+)', x)
        if num is None and mn:
            num = mn.group(1)
        ev.append({'s': cur, 'h': int(sc.group(1)), 'a': int(sc.group(2)), 'x': x, 't': team, 'n': num})
    ev.reverse()
    # Agrupar en rallies (el toque que cierra lleva el marcador nuevo).
    rallies = []
    curr = []
    last_tot = {}
    for e in ev:
        tot = e['h'] + e['a']
        lt = last_tot.get(e['s'])
        if lt is None:
            last_tot[e['s']] = tot if not curr else lt
            lt = last_tot[e['s']]
            if lt is None:
                last_tot[e['s']] = tot
                lt = tot
        curr.append(e)
        if tot > lt:
            rallies.append(curr)
            curr = []
            last_tot[e['s']] = tot
    # El primer rally de la ventana puede venir cortado: se descarta si no empieza con saque.
    pts = {(p['s'], p['h'], p['a']): p for p in m['points']}
    R = {'h': nuevo(), 'a': nuevo()}
    rot = {'h': {}, 'a': {}}
    jug = {'h': {}, 'a': {}}
    recv = {'h': {}, 'a': {}}
    cub = 0
    for ra in rallies:
        first = ra[0]
        if not re.search(r'serve in play|service ace|service error', first['x']):
            continue
        S = first['t']
        if S not in ('h', 'a'):
            continue
        Rv = 'a' if S == 'h' else 'h'
        last = ra[-1]
        # Ganador: el que sumo en el ultimo toque.
        prevscore = (first['h'], first['a']) if 'service' not in first['x'] or 'serve in play' in first['x'] else None
        p = pts.get((last['s'], last['h'], last['a']))
        w = p['w'] if p and p.get('w') else None
        if w is None:
            continue
        cub += 1
        if 'service error' in first['x']:
            continue  # sin recepcion
        R[Rv]['rec'] += 1
        R[S]['bp_n'] += 1
        if w == S:
            R[S]['bp_w'] += 1
        if w == Rv:
            R[Rv]['so'] += 1
        r_rot = p.get('r' + Rv) if p else None
        rr = rot[Rv].setdefault(str(r_rot) if r_rot else '?', {'rec': 0, 'fbk': 0, 'so': 0, 'k1': [0, 0, 0, 0]})
        rr['rec'] += 1
        if w == Rv:
            rr['so'] += 1
        receptor = None
        for e in ra:
            if 'reception' in e['x']:
                mm = re.search(r'#(\d+) reception', e['x'])
                receptor = mm.group(1) if mm else e['n']
        if receptor:
            q = recv[Rv].setdefault(receptor, {'rec': 0, 'fbk': 0, 'so': 0, 'err': 0})
            q['rec'] += 1
            if w == Rv:
                q['so'] += 1
            if 'service ace' in first['x'] or any('reception error' in e['x'] for e in ra):
                q['err'] += 1
        # Ataques en orden
        atk = []
        for e in ra:
            x = e['x']
            if re.search(r'#\d+ (kill|attack error|attack blocked|attack dug by)', x) or re.search(r'· +#\d+ attack error', x):
                mm = re.search(r'#(\d+) (kill|attack error|attack blocked|attack dug by)', x)
                kind = mm.group(2)
                res_ = {'kill': 0, 'attack error': 1, 'attack blocked': 2, 'attack dug by': 3}[kind]
                t = e['t']
                atk.append([t, mm.group(1), res_])
        # Equipo del atacante cuando falta: alterna desde la recepcion.
        nxt = Rv
        for a_ in atk:
            if a_[0] not in ('h', 'a'):
                a_[0] = nxt
            nxt = ('a' if a_[0] == 'h' else 'h') if a_[2] == 3 else a_[0]
        # Un bloqueo que cierra despues de "attack blocked" no es otro ataque.
        k1_hecho = False
        rival_ataco = False
        k2_en_rally = False
        for t, n, r_ in atk:
            if t == Rv and not k1_hecho and not rival_ataco:
                fase = 'k1'
                k1_hecho = True
                if r_ == 0:
                    R[Rv]['fbk'] += 1
                    rr['fbk'] += 1
                    if receptor:
                        recv[Rv][receptor]['fbk'] += 1
                rr['k1'][r_] += 1
                at = rr.setdefault('att', {}).setdefault(n or '?', [0, 0, 0, 0])
                at[r_] += 1
            elif t == S:
                fase = 'k2'
                rival_ataco = True
                k2_en_rally = True
            else:
                fase = 'tr'
            R[t][fase][r_] += 1
            j = jug[t].setdefault(n, {'k1': [0, 0, 0, 0], 'k2': [0, 0, 0, 0], 'tr': [0, 0, 0, 0]})
            j[fase][r_] += 1
        if not k1_hecho:
            R[Rv]['sin_ataque'] += 1
        if k2_en_rally:
            R[S]['k2_ral'] += 1
            if w == S:
                R[S]['k2_pts'] += 1
    total = sum(len(v) for v in [m['points']])
    tot_r = sum(s[0] + s[1] for s in m['sets'])
    res[gid] = {'cub': cub, 'tot': tot_r, 'equipos': {'h': home, 'a': away}, 'fases': R, 'rot': rot, 'jug': jug, 'recv': recv}

for m in LISTA:
    m['fases'] = res.get(m['id'], {})
json.dump(LISTA, open(BB, 'w'), ensure_ascii=False)


def pct(a, b):
    return ('%d%%' % round(100.0 * a / b)) if b else '—'


def eff(v):
    ta = sum(v)
    return ('%+.3f' % ((v[0] - v[1] - v[2]) / ta)).replace('+0.', '.').replace('-0.', '-.') if ta else '—'


for gid, r in res.items():
    m = partidos[gid]
    print(gid, m['home'], 'vs', m['away'], 'rallies cubiertos', r['cub'], 'de', r['tot'])
    for side in ('h', 'a'):
        F = r['fases'][side]
        print('  ', r['equipos'][side][:22].ljust(22), 'rec', F['rec'], 'FBSO', pct(F['fbk'], F['rec']), 'SO', pct(F['so'], F['rec']),
              'K1', F['k1'], eff(F['k1']), 'K2', F['k2'], 'kill%', pct(F['k2'][0], sum(F['k2'])), eff(F['k2']), 'TR', F['tr'], 'sinAtk', F['sin_ataque'])
