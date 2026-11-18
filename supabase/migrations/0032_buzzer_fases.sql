-- =====================================================================
-- ANGELS - 0032 Fases de juego del Buzzer Beater (K1, FBSO y K2)
-- ---------------------------------------------------------------------
-- Pedido de Carlos (17 nov. 2026): first ball side-out y efectividad en K2
-- de ADC y de sus rivales. Salen del jugada a jugada oficial (el sitio del
-- torneo publica los ultimos 200 toques de cada partido), calculados por
-- herramientas/buzzer/bb_fases.py y guardados por partido en "fases":
--   cub/tot  rallies con detalle / rallies del partido
--   fases    por lado (h/a): rec, fbk, so, k1/k2/tr [kills, errores,
--            bloqueados, defendidos], sin_ataque, bp_n, bp_w, k2_ral, k2_pts
--   rot      por lado y rotacion de quien recibe: rec, fbk, so, k1, att
--   jug      por lado y jugador: k1, k2, tr
--   recv     por lado y receptor: rec, fbk, so, err
-- Solo agrega una columna y actualiza buzzer_data(). Sin DROP, DELETE ni
-- TRUNCATE.
-- =====================================================================

alter table angels.buzzer_partidos add column if not exists fases jsonb not null default '{}'::jsonb;

create or replace function angels.buzzer_data()
returns jsonb
language sql
stable
security definer
set search_path to 'angels', 'pg_temp'
as $$
  select jsonb_build_object(
    'abierto',   c.abierto,
    'cargado',   c.cargado_at,
    'partidos',  coalesce((select jsonb_agg(jsonb_build_object(
                    'id', p.id, 'slug', p.slug, 'ronda', p.ronda, 'ronda_es', p.ronda_es, 'ronda_orden', p.ronda_orden,
                    'llave', p.llave, 'jugado_at', p.jugado_at, 'cancha', p.cancha, 'local', p.local, 'visitante', p.visitante,
                    'estado', p.estado, 'sets', p.sets, 'sets_local', p.sets_local, 'sets_visita', p.sets_visita,
                    'orden_saque', p.orden_saque, 'video', p.video, 'puntos', p.puntos, 'completo', p.completo, 'fases', p.fases)
                    order by p.ronda_orden, p.jugado_at, p.id) from angels.buzzer_partidos p), '[]'::jsonb),
    'box',       coalesce((select jsonb_agg(jsonb_build_array(
                    b.partido_id, b.lado, b.num, b.nombre, b.sp, b.k, b.e, b.ta, b.a, b.sta, b.sa, b.se, b.sva,
                    b.re, b.rta, b.dig, b.bs, b.be, b.bhe, b.pts)
                    order by b.partido_id, b.lado, b.num) from angels.buzzer_box b), '[]'::jsonb)
  )
  from angels.buzzer_config c where c.id = 'buzzer-2026';
$$;
revoke all on function angels.buzzer_data() from public, anon, authenticated;
