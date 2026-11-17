#!/usr/bin/env python3
# Lee las paginas de partido de buzzerbeaterpr.com (Junior Masculino) y
# produce un JSON por partido: cabecera, sets, box score de los dos equipos,
# orden de saque, video y la lista de puntos (con quien saco y en que
# rotacion estaba ADC cuando se pudo saber).
# Uso: python3 -I bb_parse.py <carpeta_html> <salida.json>
import re, sys, os, json, html, glob, datetime

RAW = sys.argv[1]
OUT = sys.argv[2]
ADC = 'ADC Bayamón'

ROUND_ES = {
    'Round of 64': ('Ronda de 64', 0), 'Round of 32': ('Ronda de 32', 1),
    'Round of 16': ('Octavos de final', 2), 'Quarterfinal': ('Cuartos de final', 3),
    'Semifinal': ('Semifinal', 4), 'Final': ('Final', 5),
}
BOX_COLS = ['sp', 'k', 'e', 'ta', None, 'a', 'sta', None, 'sa', 'se', 'sva', None,
            're', 'rta', None, 'dig', 'bs', 'be', 'bhe', 'pts']


def txt(s):
    s = re.sub(r'<[^>]+>', ' ', s)
    return re.sub(r'\s+', ' ', html.unescape(s)).strip()


def num(s):
    try:
        return float(s) if '.' in s else int(s)
    except Exception:
        return 0


def parse_box(h, label):
    i = -1
    for m in re.finditer(r'aria-label="([^"]*) live volleyball box score"', h):
        if html.unescape(m.group(1)) == label:
            i = m.start()
    if i < 0:
        return None
    j = h.find('</table>', i)
    body = h[i:j]
    rows = []
    for tr in re.findall(r'<tr>(.*?)</tr>', body[body.find('<tbody>'):], re.S):
        tds = re.findall(r'<td[^>]*>(.*?)</td>', tr, re.S)
        if len(tds) < 22:
            continue
        nm = txt(tds[1])
        link = re.search(r'volleyball-leaders/[a-z0-9-]*-(\d+)"', tds[1])
        no = txt(tds[0])
        if not no or nm.lower().startswith('total'):
            continue
        r = {'num': no, 'name': nm, 'pid': link.group(1) if link else None}
        for c, v in zip(BOX_COLS, tds[2:]):
            if c:
                r[c] = num(txt(v))
        rows.append(r)
    return rows


def parse_match(path):
    h = open(path, encoding='utf-8').read()
    slug = os.path.basename(path)[2:-5]
    gid = re.search(r'-(g\d+-\d+)$', slug).group(1)
    board = h[h.find('class="bz-board"'):]
    meta = [txt(x) for x in re.findall(r'<span(?: class="sport")?>(.*?)</span>', board[:board.find('</div>')])]
    when = next((m for m in meta if re.match(r'[A-Z][a-z]{2} \d', m)), '')
    court = next((m for m in meta if m.startswith('Court')), '')
    rnd = next((m for m in meta if any(m.startswith(k) for k in ROUND_ES)), '')
    strip = board[board.find('class="bz-strip"'):board.find('class="bz-strip"') + 4000]
    sides = re.findall(r'<small>(Home|Away)</small>\s*<strong>(.*?)</strong>', strip, re.S)
    names = {}
    for lab, inner in sides:
        names[lab] = html.unescape(txt(inner)) if 'bz-team-a' in inner else None
    home, away = names.get('Home'), names.get('Away')
    status_raw = txt(re.search(r'class="bz-status[^"]*">(.*?)</div>', board, re.S).group(1))
    if 'Pending' in status_raw:
        status = 'pendiente'
    elif 'Live' in status_raw:
        status = 'en_vivo'
    else:
        status = 'final'
    # Fecha y hora de Puerto Rico (UTC-4 todo el ano).
    played = None
    m = re.match(r'([A-Z][a-z]{2} \d{1,2}, \d{4}) · (\d{2}:\d{2} [AP]M)', when)
    if m:
        dt = datetime.datetime.strptime(m.group(1) + ' ' + m.group(2), '%b %d, %Y %I:%M %p')
        played = dt.strftime('%Y-%m-%dT%H:%M:00-04:00')
    # Sets por equipo, de la tabla S1 S2 S3.
    sets = []
    rhe = re.search(r'class="bz-rhe"[^>]*>(.*?)</div>', board, re.S)
    if rhe:
        cells = [txt(c) for c in re.findall(r'<span[^>]*>(.*?)</span>', rhe.group(1), re.S)]
        nset = sum(1 for c in cells if re.match(r'^S\d$', c))
        row = {}
        k = cells.index('Sets') + 1 if 'Sets' in cells else 0
        while k < len(cells):
            row[cells[k]] = [num(x) for x in cells[k + 1:k + 1 + nset + 1]]
            k += nset + 2
        hr, ar = row.get(home), row.get(away)
        if hr and ar:
            for s in range(nset):
                sets.append([hr[s], ar[s]])
            hsets, asets = hr[-1], ar[-1]
        else:
            hsets = asets = 0
    else:
        hsets = asets = 0
    box_h = parse_box(h, home) or []
    box_a = parse_box(h, away) or []
    # Jugador del sitio -> (equipo, numero)
    who = {}
    for side, rows in (('h', box_h), ('a', box_a)):
        for r in rows:
            if r['pid']:
                who[r['pid']] = (side, r['num'])
    # Orden de saque (foto final).
    order = {}
    t = txt(h[h.find('Live court'):h.find('How points were won')]) if 'Live court' in h else ''
    for side, team in (('h', home), ('a', away)):
        if not team:
            continue
        mm = re.search(re.escape(team) + r' Serving order ((?:\d+ ){6})', t)
        if mm:
            order[side] = mm.group(1).split()
    # Video: id del canal y segundo de inicio.
    vid = re.search(r'youtube\.com/watch\?v=([A-Za-z0-9_-]+)(?:&amp;t=(\d+)s)?', h)
    video = {'id': vid.group(1), 't': int(vid.group(2)) if vid and vid.group(2) else None} if vid else None

    # Puntos de la pista de video (la lista mas completa de quien gano cada punto).
    pts = {}
    for m in re.finditer(r'<button type="button" class="bzw-pc ([^"]*)"([^>]*)>', h):
        cls, attrs = m.group(1), m.group(2)
        a = dict(re.findall(r'data-bzw-([a-z-]+)="([^"]*)"', attrs))
        sc = re.match(r'(\d+)\D+(\d+)', html.unescape(a.get('score', '')))
        if not sc:
            continue
        kind = re.search(r'k-([a-z]+)', cls)
        kind = kind.group(1) if kind else 'point'
        s = int(a.get('set', '0'))
        hs, as_ = int(sc.group(1)), int(sc.group(2))
        w = 'h' if a.get('won') == 'home' else 'a'
        pl = who.get(a.get('who', ''), (None, None))
        pts[(s, hs, as_)] = {'s': s, 'h': hs, 'a': as_, 'w': w, 'k': kind,
                             'p': pl[1], 'ps': pl[0], 't': int(float(a['t'])) if a.get('t') else None}
    # Jugada a jugada (ultimos 200 toques): saque, tipo de error y anotador.
    feed = h[h.find('<h2>Play-by-Play</h2>'):]
    feed = feed[:feed.find('class="bz-actions"')] if 'class="bz-actions"' in feed else feed
    cur = 0
    events = []
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
        link = re.search(r'volleyball-leaders/[a-z0-9-]*-(\d+)"', part)
        t = re.search(r'data-bzw-t="(\d+)"', part)
        events.append({'s': cur, 'h': int(sc.group(1)), 'a': int(sc.group(2)), 'x': txt(st.group(1)),
                       'pid': link.group(1) if link else None, 't': int(t.group(1)) if t else None})
    events.reverse()  # cronologico
    # Los toques de un rally llevan el marcador de antes; el toque que cierra
    # el rally lleva el marcador nuevo. Se agrupa en orden cronologico.
    rallies = {}
    cur_ev = []
    last_tot = {}
    for ev in events:
        tot = ev['h'] + ev['a']
        lt = last_tot.get(ev['s'])
        if lt is None:
            last_tot[ev['s']] = tot if not cur_ev else lt
            lt = last_tot[ev['s']]
        cur_ev.append(ev)
        if tot > lt:
            rallies[(ev['s'], ev['h'], ev['a'])] = {'ev': cur_ev}
            cur_ev = []
            last_tot[ev['s']] = tot
    # Para cada rally del feed: quien saco y como termino.
    feed_info = {}
    for key, r in rallies.items():
        srv = None
        end = None
        for ev in r['ev']:
            x = ev['x']
            pl = who.get(ev['pid'], (None, None))
            mm = re.match(r'^(?:(.+?) ·\s+)?#(\d+) (serve in play|service ace|service error)', x)
            if mm:
                team = mm.group(1)
                if pl[0]:
                    srv = (pl[0], pl[1])
                elif team:
                    srv = ('h' if team.strip() == home else 'a', mm.group(2))
            if re.search(r'kill|ace|error|block on|point', x):
                end = ev
        feed_info[key] = {'srv': srv, 'end': end['x'] if end else None}
    # Puntos que solo aparecen en el feed (antes de que empezara el video).
    for key, fi in feed_info.items():
        s, hs, as_ = key
        if key in pts or (hs == 0 and as_ == 0):
            continue
        x = fi['end'] or ''
        # El feed guarda el marcador despues del punto: el que subio gano.
        pts[key] = {'s': s, 'h': hs, 'a': as_, 'w': None, 'k': 'point', 'p': None, 'ps': None, 't': None}
    # Ordenar y deducir ganador y saque.
    sets_pts = {}
    for p in pts.values():
        sets_pts.setdefault(p['s'], []).append(p)
    out_pts = []
    complete = {}
    for s in sorted(sets_pts):
        lst = sorted(sets_pts[s], key=lambda p: (p['h'] + p['a'], p['h']))
        fin = sets[s - 1] if s - 1 < len(sets) else None
        complete[s] = bool(fin) and len(lst) == fin[0] + fin[1] and all(
            lst[i]['h'] + lst[i]['a'] == i + 1 for i in range(len(lst)))
        last = None
        for p in lst:
            if p['w'] is None and last is not None and p['h'] + p['a'] == last['h'] + last['a'] + 1:
                p['w'] = 'h' if p['h'] > last['h'] else 'a'
            elif p['w'] is None and p['h'] + p['a'] == 1:
                p['w'] = 'h' if p['h'] == 1 else 'a'
            # Saque: el que gano el punto anterior saca este. Si el feed lo dice, manda el feed.
            fi = feed_info.get((s, p['h'], p['a']))
            if fi and fi['srv']:
                p['sv'] = fi['srv'][0]
                p['sn'] = fi['srv'][1]
            elif last is not None and last['h'] + last['a'] + 1 == p['h'] + p['a'] and last.get('w'):
                p['sv'] = last['w']
            if p['k'] == 'ace' and p.get('ps'):
                p['sv'] = p['ps']
                p['sn'] = p['p']
            if fi and fi['end']:
                p['x'] = fi['end']
            last = p
            out_pts.append(p)
    # Rotacion de cada equipo: se ancla con los saques conocidos y avanza con cada side-out.
    for side in ('h', 'a'):
        od = order.get(side)
        if not od:
            continue
        for s in sorted(sets_pts):
            lst = [p for p in out_pts if p['s'] == s]
            # idx = posicion en el orden de saque del que saca (o sacaria) en ese rally para este equipo
            n = len(lst)
            idx = [None] * n
            for i, p in enumerate(lst):
                if p.get('sv') == side and p.get('sn') in od:
                    idx[i] = od.index(p['sn'])
            # Propagar: si en el rally i este equipo saca con idx k, en el i+1:
            #  - si gano el punto, sigue sacando el mismo (k)
            #  - si perdio, el rival saca; este equipo sigue en k hasta que gane (side-out) -> k+1
            def step(i, k):
                p = lst[i]
                if not p.get('w'):
                    return None
                if p.get('sv') == side:
                    return k if p['w'] == side else k  # pierde el saque: la rotacion no cambia
                if p.get('sv') and p['w'] == side:
                    return (k + 1) % 6  # side-out: rota
                if p.get('sv'):
                    return k
                return None
            # Definir "k" como el ultimo servidor de este equipo (rotacion actual).
            cur = [None] * n
            for i in range(n):
                if idx[i] is not None:
                    cur[i] = idx[i]
            changed = True
            while changed:
                changed = False
                for i in range(n - 1):
                    if cur[i] is not None and cur[i + 1] is None:
                        nk = step(i, cur[i])
                        if nk is not None:
                            cur[i + 1] = nk
                            changed = True
                for i in range(n - 1, 0, -1):
                    if cur[i] is not None and cur[i - 1] is None:
                        p = lst[i - 1]
                        if not p.get('w') or not p.get('sv'):
                            continue
                        if p['sv'] != side and p['w'] == side:
                            cur[i - 1] = (cur[i] - 1) % 6
                        else:
                            cur[i - 1] = cur[i]
                        changed = True
            # Rotacion al estilo de Carlos (orden de saque): R = posicion del servidor
            # tomando como R1 al colocador titular; para los demas equipos R1 = primer
            # numero del orden publicado.
            box = box_h if side == 'h' else box_a
            setter = max(box, key=lambda r: r.get('a', 0))['num'] if box else None
            if side == ('h' if home == ADC else 'a') and '24' in od:
                base = od.index('24')
            elif setter in od:
                base = od.index(setter)
            else:
                base = 0
            for i, p in enumerate(lst):
                if cur[i] is not None:
                    # Al recibir, el equipo esta en la rotacion anterior al proximo saque.
                    k = cur[i]
                    r = (k - base) % 6 + 1
                    p['r' + side] = r
                    p['sv' + side] = od[k]
    for p in out_pts:
        for kk in ('ps', 'p', 'sn', 'x'):
            if p.get(kk) is None:
                p.pop(kk, None)
        if p.get('t') is None:
            p.pop('t', None)
    rnd_es, rnd_ord = ROUND_ES.get(rnd, (rnd, 9))
    rnd_n = re.search(r'-(\d+)-g\d+', slug)
    return {
        'id': gid, 'slug': slug, 'round': rnd, 'round_es': rnd_es, 'round_order': rnd_ord,
        'bracket_no': int(rnd_n.group(1)) if rnd_n else None,
        'played_at': played, 'court': court.replace('Court', 'Cancha'), 'home': home, 'away': away,
        'status': status, 'sets': sets, 'setter': {}, 'home_sets': hsets, 'away_sets': asets,
        'video': video, 'order': order, 'box': {'h': box_h, 'a': box_a}, 'points': out_pts,
        'complete': complete,
    }


res = []
for f in sorted(glob.glob(os.path.join(RAW, 'm_*.html'))):
    try:
        m = parse_match(f)
    except Exception as e:
        print('ERROR', f, e)
        continue
    res.append(m)
json.dump(res, open(OUT, 'w'), ensure_ascii=False)
for m in res:
    pts = m['points']
    hasr = sum(1 for p in pts if 'rh' in p or 'ra' in p)
    print(m['id'], m['round'], m['status'], m['home'], 'vs', m['away'], m['sets'], 'box', len(m['box']['h']), len(m['box']['a']),
          'pts', len(pts), 'rot', hasr, m['complete'], m['order'])
