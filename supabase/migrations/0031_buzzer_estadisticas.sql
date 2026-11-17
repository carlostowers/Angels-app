-- =====================================================================
-- ANGELS - 0031 Estadisticas del Buzzer Beater 2026 (Junior Masculino)
-- ---------------------------------------------------------------------
-- Pedido de Carlos (17 nov. 2026): una pagina con todas las estadisticas
-- del torneo, acumuladas juego a juego: las de ADC y las de los rivales
-- (sirven para el scouting del playbook).
--
-- Decisiones de Carlos:
--  - La ven todos los jugadores, pero el coach la abre y la cierra, como
--    el examen (buzzer_config.abierto).
--  - La data la carga Claude despues de cada juego, desde la pagina oficial
--    del torneo (buzzerbeaterpr.com). La app no lee el sitio del torneo.
--  - Solo para el Buzzer Beater (ultimo torneo de la temporada).
--
-- Tablas:
--  buzzer_config   una fila: abierto o cerrado, y cuando se cargo la data.
--  buzzer_partidos un partido por fila: cabecera, sets, orden de saque,
--                  video y la lista de puntos (quien saco, quien gano, como,
--                  rotacion de cada equipo y segundo del video).
--  buzzer_box      box score por jugador de los dos equipos de cada partido.
--
-- Nadie lee las tablas directo salvo el staff. El jugador las recibe con
-- angels.player_buzzer(p_token), que valida su enlace y solo devuelve la
-- data si la pagina esta abierta. El jugador no escribe nada.
-- Sin DROP, DELETE ni TRUNCATE.
-- =====================================================================

create table angels.buzzer_config (
  id           text        primary key default 'buzzer-2026',
  abierto      boolean     not null default false,
  cargado_at   timestamptz,
  updated_at   timestamptz not null default now(),
  constraint buzzer_config_id_chk check (id = 'buzzer-2026')
);
insert into angels.buzzer_config (id) values ('buzzer-2026');

create table angels.buzzer_partidos (
  id           text        primary key,
  slug         text        not null,
  ronda        text        not null,
  ronda_es     text        not null,
  ronda_orden  smallint    not null default 9,
  llave        smallint,
  jugado_at    timestamptz,
  cancha       text,
  local        text,
  visitante    text,
  estado       text        not null default 'pendiente',
  sets         jsonb       not null default '[]'::jsonb,
  sets_local   smallint    not null default 0,
  sets_visita  smallint    not null default 0,
  orden_saque  jsonb       not null default '{}'::jsonb,
  video        jsonb,
  puntos       jsonb       not null default '[]'::jsonb,
  completo     jsonb       not null default '{}'::jsonb,
  updated_at   timestamptz not null default now(),
  constraint buzzer_partidos_id_chk     check (id ~ '^g[0-9]{1,3}-[0-9]{1,5}$'),
  constraint buzzer_partidos_estado_chk check (estado = any (array['pendiente','en_vivo','final']))
);
create index buzzer_partidos_ronda_idx on angels.buzzer_partidos (ronda_orden, jugado_at);

create table angels.buzzer_box (
  partido_id   text        not null references angels.buzzer_partidos(id) on delete cascade,
  lado         text        not null,
  equipo       text        not null,
  num          text        not null,
  nombre       text        not null,
  sitio_id     text,
  sp   smallint not null default 0,
  k    smallint not null default 0,
  e    smallint not null default 0,
  ta   smallint not null default 0,
  a    smallint not null default 0,
  sta  smallint not null default 0,
  sa   smallint not null default 0,
  se   smallint not null default 0,
  sva  smallint not null default 0,
  re   smallint not null default 0,
  rta  smallint not null default 0,
  dig  smallint not null default 0,
  bs   smallint not null default 0,
  be   smallint not null default 0,
  bhe  smallint not null default 0,
  pts  numeric(5,1) not null default 0,
  primary key (partido_id, lado, num),
  constraint buzzer_box_lado_chk check (lado = any (array['h','a']))
);
create index buzzer_box_equipo_idx on angels.buzzer_box (equipo);

alter table angels.buzzer_config   enable row level security;
alter table angels.buzzer_partidos enable row level security;
alter table angels.buzzer_box      enable row level security;
create policy buzzer_config_staff   on angels.buzzer_config   for select to authenticated using ((select angels.is_staff()));
create policy buzzer_partidos_staff on angels.buzzer_partidos for select to authenticated using ((select angels.is_staff()));
create policy buzzer_box_staff      on angels.buzzer_box      for select to authenticated using ((select angels.is_staff()));
revoke all on angels.buzzer_config, angels.buzzer_partidos, angels.buzzer_box from anon, authenticated;
grant select on angels.buzzer_config, angels.buzzer_partidos, angels.buzzer_box to authenticated;
grant all on angels.buzzer_config, angels.buzzer_partidos, angels.buzzer_box to service_role;

-- Todo el torneo en un solo JSON (lo usan el staff y el jugador).
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
                    'orden_saque', p.orden_saque, 'video', p.video, 'puntos', p.puntos, 'completo', p.completo)
                    order by p.ronda_orden, p.jugado_at, p.id) from angels.buzzer_partidos p), '[]'::jsonb),
    'box',       coalesce((select jsonb_agg(jsonb_build_array(
                    b.partido_id, b.lado, b.num, b.nombre, b.sp, b.k, b.e, b.ta, b.a, b.sta, b.sa, b.se, b.sva,
                    b.re, b.rta, b.dig, b.bs, b.be, b.bhe, b.pts)
                    order by b.partido_id, b.lado, b.num) from angels.buzzer_box b), '[]'::jsonb)
  )
  from angels.buzzer_config c where c.id = 'buzzer-2026';
$$;
revoke all on function angels.buzzer_data() from public, anon, authenticated;

-- Jugador: si la pagina esta cerrada, solo sabe que esta cerrada.
create or replace function angels.player_buzzer(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_p angels.players%rowtype;
  v_ab boolean;
begin
  v_p := angels.exam_jugador(p_token);
  select abierto into v_ab from angels.buzzer_config where id = 'buzzer-2026';
  if not coalesce(v_ab, false) then
    return jsonb_build_object('abierto', false);
  end if;
  return angels.buzzer_data();
end;
$$;

-- Staff: toda la data, abierta o cerrada.
create or replace function angels.staff_buzzer()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'angels', 'pg_temp'
as $$
begin
  if not angels.is_staff() then raise exception 'Solo staff' using errcode = '42501'; end if;
  return angels.buzzer_data();
end;
$$;

-- Staff: abrir o cerrar la pagina para los jugadores.
create or replace function angels.staff_buzzer_config(p_abierto boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare v boolean;
begin
  if not angels.is_staff() then raise exception 'Solo staff' using errcode = '42501'; end if;
  update angels.buzzer_config set abierto = coalesce(p_abierto, abierto), updated_at = now()
   where id = 'buzzer-2026' returning abierto into v;
  return jsonb_build_object('ok', true, 'abierto', v);
end;
$$;

revoke all on function angels.player_buzzer(text) from public;
revoke all on function angels.staff_buzzer() from public, anon;
revoke all on function angels.staff_buzzer_config(boolean) from public, anon;
grant execute on function angels.player_buzzer(text) to anon, authenticated;
grant execute on function angels.staff_buzzer() to authenticated;
grant execute on function angels.staff_buzzer_config(boolean) to authenticated;
