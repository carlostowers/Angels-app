-- =====================================================================
-- 0029 · Quien esta en la app ahora mismo
-- ---------------------------------------------------------------------
-- Pedido de Carlos (16 nov. 2026, opcion A): ver en la pagina Uso del
-- staff quien esta adentro en este momento, en que parte de la app o en
-- que juego.
--
-- Mientras la app o un juego esta abierto en pantalla con el enlace del
-- jugador, el telefono llama angels.player_ping cada minuto. Se guarda una
-- sola fila por jugador (la ultima vez y donde estaba): cada aviso
-- reemplaza al anterior, asi que no crece. El historial sigue en
-- angels.app_events. Sin IP, dispositivo ni ubicacion.
-- Lo lee solo el staff, con angels.staff_presencia.
-- =====================================================================

create table angels.app_presence (
  player_id text        primary key references angels.players(id) on delete cascade,
  at        timestamptz not null default now(),
  desde     timestamptz not null default now(),
  donde     text        not null,
  ref       text,
  constraint app_presence_donde_chk check (donde ~ '^[a-z_]{2,20}$'),
  constraint app_presence_ref_chk   check (ref is null or ref ~ '^[a-z0-9_-]{2,40}$')
);
comment on table angels.app_presence is
  'Ultimo aviso de cada jugador con la app o un juego abierto (una fila por jugador). Solo lo lee el staff.';

alter table angels.app_presence enable row level security;
create policy app_presence_staff on angels.app_presence for select to authenticated
  using ((select angels.is_staff()));
revoke all on angels.app_presence from anon, authenticated;
grant select on angels.app_presence to authenticated;
grant all on angels.app_presence to service_role;

-- El jugador avisa que sigue adentro. donde: la vista de la app (hoy,
-- checkin, juegos, ...) o 'juego' con el juego en p_ref. "desde" se
-- conserva mientras siga en el mismo sitio sin cortes de mas de 3 minutos.
create or replace function angels.player_ping(p_token text, p_donde text, p_ref text default null)
returns void
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_player angels.players%rowtype;
  v_donde  text := lower(btrim(coalesce(p_donde, '')));
  v_ref    text := nullif(lower(btrim(coalesce(p_ref, ''))), '');
begin
  if p_token is null or length(p_token) < 32 then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  select * into v_player from angels.players where access_token = p_token;
  if not found then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  if v_player.status = 'pausado' then
    return;
  end if;
  if v_donde !~ '^[a-z_]{2,20}$' then
    v_donde := 'app';
  end if;
  if v_donde = 'juego' then
    if v_ref is null or v_ref <> all (array['keepup','longspike','bareboru','bareboru6','keepup2']) then
      raise exception 'Juego no valido';
    end if;
  else
    v_ref := null;
  end if;
  insert into angels.app_presence as a (player_id, at, desde, donde, ref)
  values (v_player.id, now(), now(), v_donde, v_ref)
  on conflict (player_id) do update
     set desde = case when a.at > now() - interval '3 minutes'
                       and a.donde = excluded.donde
                       and a.ref is not distinct from excluded.ref
                      then a.desde else now() end,
         at = now(), donde = excluded.donde, ref = excluded.ref;
end;
$$;
revoke all on function angels.player_ping(text, text, text) from public;
grant execute on function angels.player_ping(text, text, text) to anon, authenticated;

-- Para el staff: quien aviso en los ultimos p_min minutos (por defecto 15).
-- La app marca "ahora" a los de los ultimos 2 minutos.
create or replace function angels.staff_presencia(p_min integer default 15)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_min integer := least(greatest(coalesce(p_min, 15), 1), 120);
begin
  if not angels.is_staff() then
    raise exception 'Solo staff' using errcode = '28000';
  end if;
  return jsonb_build_object(
    'ahora', now(),
    'lista', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', a.player_id, 'at', a.at, 'desde', a.desde, 'donde', a.donde, 'ref', a.ref)
                order by a.at desc), '[]'::jsonb)
                from angels.app_presence a
                join angels.players p on p.id = a.player_id
               where a.at > now() - make_interval(mins => v_min) and p.status <> 'pausado'));
end;
$$;
revoke all on function angels.staff_presencia(integer) from public, anon;
grant execute on function angels.staff_presencia(integer) to authenticated;
