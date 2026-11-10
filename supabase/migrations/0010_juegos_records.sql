-- =====================================================================
-- ANGELS - 0010 Juegos: récords permanentes de Keep It Up y Long Spike
-- ---------------------------------------------------------------------
-- Una fila por jugador y por juego con su mejor marca. Los récords nunca
-- se borran (decisión de Carlos, 6 nov. 2026). Tabla aislada de los datos
-- de salud: solo puntuaciones de juego.
-- El jugador escribe solo por RPC con su token; la RPC revisa que la marca
-- sea posible para el tiempo jugado (freno básico a trampas).
-- El top se muestra con número y primer nombre (son menores).
-- El staff lee la tabla directo (RLS por is_staff()).
-- =====================================================================

create table angels.game_records (
  player_id      text        not null references angels.players(id),
  game           text        not null,
  best_score     integer     not null default 0,
  best_level     integer,
  best_meta      jsonb       not null default '{}'::jsonb,
  best_at        timestamptz,
  plays          integer     not null default 0,
  last_played_at timestamptz,
  primary key (player_id, game),
  constraint game_records_game_chk check (game = any (array['keepup','longspike'])),
  constraint game_records_score_chk check (best_score >= 0)
);
create index game_records_game_score on angels.game_records (game, best_score desc);

alter table angels.game_records enable row level security;
create policy game_records_staff on angels.game_records for all to authenticated
  using ((select angels.is_staff())) with check ((select angels.is_staff()));
grant select, insert, update on angels.game_records to authenticated, service_role;
revoke all on angels.game_records from anon;

-- ---------------------------------------------------------------------
-- Guardar una partida
-- p_meta: keepup    -> { "level": int, "touches": int, "secs": num }
--         longspike -> { "secs": num, "v0": num }
-- ---------------------------------------------------------------------
create or replace function angels.player_game_submit(p_token text, p_game text, p_score integer, p_meta jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_player  angels.players%rowtype;
  v_prev    angels.game_records%rowtype;
  v_secs    numeric;
  v_level   integer;
  v_touches integer;
  v_record  boolean := false;
  v_best    integer;
begin
  if p_token is null or length(p_token) < 32 then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  select * into v_player from angels.players where access_token = p_token;
  if not found then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  if v_player.status = 'pausado' then
    raise exception 'Tu perfil esta en pausa. Habla con el coach.' using errcode = '28000';
  end if;
  if p_game is null or p_game <> all (array['keepup','longspike']) then
    raise exception 'Juego no valido';
  end if;
  if p_score is null or p_score < 0 then
    raise exception 'Puntuacion no valida';
  end if;

  v_secs := coalesce((p_meta->>'secs')::numeric, 0);
  if v_secs < 1 or v_secs > 7200 then
    raise exception 'Partida no valida';
  end if;

  if p_game = 'keepup' then
    v_level   := coalesce((p_meta->>'level')::integer, 1);
    v_touches := coalesce((p_meta->>'touches')::integer, 0);
    if v_level < 1 or v_touches < 0
       or v_touches > v_secs * 4 + 5
       or v_level > 1 + v_secs / 6
       or p_score > v_secs * 150 + 600 then
      raise exception 'Partida no valida';
    end if;
  else
    v_level := null;
    if p_score > 20000 or p_score > v_secs * 350 + 300 then
      raise exception 'Partida no valida';
    end if;
  end if;

  -- Freno a envios en rafaga: una partida cada 3 segundos por juego.
  select * into v_prev from angels.game_records where player_id = v_player.id and game = p_game;
  if found and v_prev.last_played_at is not null and v_prev.last_played_at > now() - interval '3 seconds' then
    raise exception 'Espera un momento';
  end if;

  if not found then
    insert into angels.game_records (player_id, game, best_score, best_level, best_meta, best_at, plays, last_played_at)
    values (v_player.id, p_game, p_score, v_level, coalesce(p_meta, '{}'::jsonb), now(), 1, now());
    v_record := p_score > 0;
    v_best := p_score;
  else
    v_record := p_score > v_prev.best_score;
    update angels.game_records
       set plays = plays + 1,
           last_played_at = now(),
           best_score = case when v_record then p_score else best_score end,
           best_level = case when v_record then v_level else best_level end,
           best_meta  = case when v_record then coalesce(p_meta, '{}'::jsonb) else best_meta end,
           best_at    = case when v_record then now() else best_at end
     where player_id = v_player.id and game = p_game;
    v_best := greatest(p_score, v_prev.best_score);
  end if;

  return jsonb_build_object('best', v_best, 'record', v_record);
end;
$$;
revoke all on function angels.player_game_submit(text, text, integer, jsonb) from public;
grant execute on function angels.player_game_submit(text, text, integer, jsonb) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Top de un juego: p_scope 'team' (su categoria) o 'club' (15M y 16M)
-- Solo numero y primer nombre; nada de salud.
-- ---------------------------------------------------------------------
create or replace function angels.player_game_board(p_token text, p_game text, p_scope text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_player angels.players%rowtype;
  v_top    jsonb;
  v_me     jsonb;
begin
  if p_token is null or length(p_token) < 32 then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  select * into v_player from angels.players where access_token = p_token;
  if not found then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  if p_game is null or p_game <> all (array['keepup','longspike']) then
    raise exception 'Juego no valido';
  end if;

  with ranked as (
    select r.player_id, r.best_score, r.best_level, p.team, p.number,
           split_part(trim(p.name), ' ', 1) as first_name,
           rank() over (order by r.best_score desc) as pos
      from angels.game_records r
      join angels.players p on p.id = r.player_id
     where r.game = p_game
       and r.best_score > 0
       and p.status = 'activo'
       and (coalesce(p_scope, 'team') = 'club' or p.team = v_player.team)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'pos', pos, 'number', number, 'name', first_name, 'team', team,
           'score', best_score, 'level', best_level, 'me', player_id = v_player.id
         ) order by pos, first_name) filter (where pos <= 10), '[]'::jsonb),
         (select jsonb_build_object('pos', pos, 'score', best_score) from ranked where player_id = v_player.id)
    into v_top, v_me
    from ranked;

  return jsonb_build_object('top', coalesce(v_top, '[]'::jsonb), 'me', v_me, 'team', v_player.team);
end;
$$;
revoke all on function angels.player_game_board(text, text, text) from public;
grant execute on function angels.player_game_board(text, text, text) to anon, authenticated;
