-- Carga el JSON de datos/buzzer-2026.json en angels.buzzer_* (upsert, sin DELETE).
-- Paso 1 (cambiar <SHA> por el commit que trae el JSON):
--   select net.http_get(url := 'https://raw.githubusercontent.com/carlostowers/angels-app/<SHA>/herramientas/buzzer/datos/buzzer-2026.json') as id;
-- Paso 2 (unos segundos despues), con el id que devolvio el paso 1 en lugar de <ID>:
with r as (
  select content::jsonb as d from net._http_response where id = <ID> and status_code = 200
), m as (
  select x as m from r, jsonb_array_elements(r.d) x
), p as (
  insert into angels.buzzer_partidos (id, slug, ronda, ronda_es, ronda_orden, llave, jugado_at, cancha, local, visitante, estado,
                                      sets, sets_local, sets_visita, orden_saque, video, puntos, completo, updated_at)
  select m->>'id', m->>'slug', m->>'round', m->>'round_es', (m->>'round_order')::smallint, nullif(m->>'bracket_no', '')::smallint,
         nullif(m->>'played_at', '')::timestamptz, m->>'court', m->>'home', m->>'away', m->>'status',
         coalesce(m->'sets', '[]'::jsonb), coalesce((m->>'home_sets')::smallint, 0), coalesce((m->>'away_sets')::smallint, 0),
         coalesce(m->'order', '{}'::jsonb), case when jsonb_typeof(m->'video') = 'object' then m->'video' end,
         coalesce(m->'points', '[]'::jsonb), coalesce(m->'complete', '{}'::jsonb), now()
  from m
  on conflict (id) do update set slug = excluded.slug, ronda = excluded.ronda, ronda_es = excluded.ronda_es, ronda_orden = excluded.ronda_orden,
    llave = excluded.llave, jugado_at = excluded.jugado_at, cancha = excluded.cancha, local = excluded.local, visitante = excluded.visitante,
    estado = excluded.estado, sets = excluded.sets, sets_local = excluded.sets_local, sets_visita = excluded.sets_visita,
    orden_saque = excluded.orden_saque, video = excluded.video, puntos = excluded.puntos, completo = excluded.completo, updated_at = now()
  returning id
), b as (
  insert into angels.buzzer_box (partido_id, lado, equipo, num, nombre, sitio_id, sp, k, e, ta, a, sta, sa, se, sva, re, rta, dig, bs, be, bhe, pts)
  select m->>'id', s.lado, s.equipo, x->>'num', x->>'name', x->>'pid',
         (x->>'sp')::smallint, (x->>'k')::smallint, (x->>'e')::smallint, (x->>'ta')::smallint, (x->>'a')::smallint, (x->>'sta')::smallint,
         (x->>'sa')::smallint, (x->>'se')::smallint, (x->>'sva')::smallint, (x->>'re')::smallint, (x->>'rta')::smallint, (x->>'dig')::smallint,
         (x->>'bs')::smallint, (x->>'be')::smallint, (x->>'bhe')::smallint, (x->>'pts')::numeric
  from m
  cross join lateral (values ('h', m->>'home', m->'box'->'h'), ('a', m->>'away', m->'box'->'a')) as s(lado, equipo, filas)
  cross join lateral jsonb_array_elements(coalesce(s.filas, '[]'::jsonb)) x
  where s.equipo is not null
  on conflict (partido_id, lado, num) do update set equipo = excluded.equipo, nombre = excluded.nombre, sitio_id = excluded.sitio_id,
    sp = excluded.sp, k = excluded.k, e = excluded.e, ta = excluded.ta, a = excluded.a, sta = excluded.sta, sa = excluded.sa, se = excluded.se,
    sva = excluded.sva, re = excluded.re, rta = excluded.rta, dig = excluded.dig, bs = excluded.bs, be = excluded.be, bhe = excluded.bhe, pts = excluded.pts
  returning 1
)
update angels.buzzer_config set cargado_at = now() where id = 'buzzer-2026'
returning (select count(*) from p) as partidos, (select count(*) from b) as filas_box;
