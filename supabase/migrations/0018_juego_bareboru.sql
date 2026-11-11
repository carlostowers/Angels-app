-- =====================================================================
-- 0018 · Juegos: BAREBORU by VOLEII (3 contra 3), tercer juego de Angels
-- ---------------------------------------------------------------------
-- Equivale a las migraciones 0013 y 0014 de STATION, en el esquema angels.
-- 1. Agrega 'bareboru' a los récords del jugador y del coach, a los tops
--    y al borrado del staff. No borra ni cambia ningún récord existente.
-- 2. Validación en el servidor del partido 3v3 a 15 con ventaja de 2.
--    p_meta: { "us": int, "them": int, "level": 1..3, "secs": num }
--    La marca debe ser exactamente
--      level x (us x 10 + max(us - them, 0) x 5 + 100 si ganó)
--    con un marcador final posible y al menos 4 s por punto jugado.
--    best_level = nivel del rival (1 fácil, 2 normal, 3 difícil).
-- 3. Tabla game_plays: una fila por partida con estadísticas de juego,
--    sin jugador (anónima). Solo números de una lista fija. Solo por RPC.
-- Las funciones se reescriben a partir de su definición vigente; si un
-- reemplazo no encuentra el texto esperado, la migración se detiene.
-- Sin DROP de tablas, DELETE ni TRUNCATE.
-- =====================================================================

alter table angels.game_records drop constraint if exists game_records_game_chk;
alter table angels.game_records add constraint game_records_game_chk
  check (game = any (array['keepup','longspike','bareboru']));
alter table angels.staff_game_records drop constraint if exists staff_game_records_game_chk;
alter table angels.staff_game_records add constraint staff_game_records_game_chk
  check (game = any (array['keepup','longspike','bareboru']));

do $mig$
declare
  f   text;
  d   text;
  n   text;
  v_bloque text := E'  elsif p_game = ''bareboru'' then\n'
    || E'    v_rivals := coalesce((p_meta->>''us'')::integer, -1);\n'
    || E'    v_diff   := coalesce((p_meta->>''them'')::integer, -1);\n'
    || E'    v_perf   := coalesce((p_meta->>''level'')::integer, 0);\n'
    || E'    if v_perf < 1 or v_perf > 3\n'
    || E'       or v_rivals < 0 or v_diff < 0 or v_rivals > 60 or v_diff > 60\n'
    || E'       or greatest(v_rivals, v_diff) < 15\n'
    || E'       or abs(v_rivals - v_diff) < 2\n'
    || E'       or (greatest(v_rivals, v_diff) > 15 and abs(v_rivals - v_diff) <> 2)\n'
    || E'       or (v_rivals + v_diff) * 4 > v_secs + 5\n'
    || E'       or p_score <> v_perf * (v_rivals * 10 + greatest(v_rivals - v_diff, 0) * 5\n'
    || E'                              + case when v_rivals > v_diff then 100 else 0 end) then\n'
    || E'      raise exception ''Partida no valida'';\n'
    || E'    end if;\n'
    || E'    v_level := v_perf;\n';
begin
  foreach f in array array[
    'angels.player_game_submit(text,text,integer,jsonb)',
    'angels.staff_game_submit(text,integer,jsonb)',
    'angels.player_game_board(text,text,text)',
    'angels.staff_game_board(text)',
    'angels.staff_game_reset(text,text,text,text)']
  loop
    d := pg_get_functiondef(f::regprocedure);
    if position('bareboru' in d) > 0 then
      raise notice 'ya tiene bareboru: %', f;
      continue;
    end if;
    n := replace(d, 'array[''keepup'',''longspike'']', 'array[''keepup'',''longspike'',''bareboru'']');
    if n = d then raise exception 'no encontre la lista de juegos en %', f; end if;
    if f like '%game_submit%' then
      d := n;
      n := replace(d, E'  v_best    integer;\n', E'  v_best    integer;\n  v_rivals  integer;\n  v_diff    integer;\n  v_perf    integer;\n');
      if n = d then raise exception 'no encontre declare en %', f; end if;
      d := n;
      n := replace(d, E'  else\n    v_level := null;\n    if p_score > 20000', v_bloque || E'  else\n    v_level := null;\n    if p_score > 20000');
      if n = d then raise exception 'no encontre la validacion de longspike en %', f; end if;
    end if;
    execute n;
  end loop;
end
$mig$;

-- ---------------------------------------------------------------------
-- Registro anónimo de partidas
-- ---------------------------------------------------------------------
create table if not exists angels.game_plays (
  id        bigint generated always as identity primary key,
  game      text        not null,
  team      text,
  is_staff  boolean     not null default false,
  played_at timestamptz not null default now(),
  stats     jsonb       not null default '{}'::jsonb,
  constraint game_plays_game_chk check (game = any (array['bareboru']))
);
create index if not exists game_plays_game_at on angels.game_plays (game, played_at desc);

alter table angels.game_plays enable row level security;
drop policy if exists game_plays_staff on angels.game_plays;
create policy game_plays_staff on angels.game_plays for select to authenticated
  using ((select angels.is_staff()));
revoke all on angels.game_plays from anon, authenticated;
grant select on angels.game_plays to authenticated;
grant select, insert, delete on angels.game_plays to service_role;

-- Solo deja pasar números de una lista fija de llaves.
create or replace function angels.game_log_clean(p_meta jsonb)
returns jsonb
language sql
immutable
set search_path to 'angels', 'pg_temp'
as $$
  select coalesce(jsonb_object_agg(k, least(100000, greatest(0, (p_meta->>k)::numeric))::integer), '{}'::jsonb)
    from unnest(array['us','them','level','secs','assist','pa','pb','pc','pd','att','kill','atterr',
                      'blocked','ace','blk','srverr','rallies','contacts','perf','taps']) as k
   where p_meta ? k and (p_meta->>k) ~ '^[0-9]{1,7}(\.[0-9]{1,3})?$';
$$;
revoke all on function angels.game_log_clean(jsonb) from public, anon, authenticated;

create or replace function angels.player_game_log(p_token text, p_game text, p_meta jsonb)
returns void
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_player angels.players%rowtype;
  v_hoy    integer;
begin
  if p_token is null or length(p_token) < 32 then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  select * into v_player from angels.players where access_token = p_token;
  if not found or v_player.status = 'pausado' then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  if p_game is null or p_game <> all (array['bareboru']) then
    raise exception 'Juego no valido';
  end if;
  -- Freno a envios en rafaga: tope diario por categoria.
  select count(*) into v_hoy from angels.game_plays
   where game = p_game and team is not distinct from v_player.team and played_at > now() - interval '1 day';
  if v_hoy >= 1500 then
    return;
  end if;
  insert into angels.game_plays (game, team, is_staff, stats)
  values (p_game, v_player.team, false, angels.game_log_clean(coalesce(p_meta, '{}'::jsonb)));
end;
$$;
revoke all on function angels.player_game_log(text, text, jsonb) from public;
grant execute on function angels.player_game_log(text, text, jsonb) to anon, authenticated;

create or replace function angels.staff_game_log(p_game text, p_meta jsonb)
returns void
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
begin
  if not angels.is_staff() then
    raise exception 'Solo staff' using errcode = '28000';
  end if;
  if p_game is null or p_game <> all (array['bareboru']) then
    raise exception 'Juego no valido';
  end if;
  insert into angels.game_plays (game, team, is_staff, stats)
  values (p_game, null, true, angels.game_log_clean(coalesce(p_meta, '{}'::jsonb)));
end;
$$;
revoke all on function angels.staff_game_log(text, jsonb) from public, anon;
grant execute on function angels.staff_game_log(text, jsonb) to authenticated;
