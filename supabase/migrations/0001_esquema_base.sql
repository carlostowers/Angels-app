-- =====================================================================
-- ANGELS (derivado de STATION v2.5.1) - 0001 ESQUEMA BASE (esquema "angels")
-- Vive dentro del proyecto Supabase de Angels-app (qagvxlenrojmgzjoywzm),
-- aislado en su propio esquema: nada de aqui lee ni toca el esquema public
-- de Angels. El cliente se conecta con db.schema = 'angels'.
-- Derivado del esquema de Plataneros (2026-10-31), adaptado a ADCJVBoys y a
-- menores de edad. Cambios frente al original:
--  * Sin body_weight (decision de Carlos).
--  * Staff = solo cuentas en staff_users (is_staff()); antes cualquier
--    usuario autenticado podia todo.
--  * Ninguna tabla se lee como anon: el jugador recibe todo por RPC.
--  * make_backup y set_updated_at sin EXECUTE para anon/authenticated.
--  * player_submit_checkin valida todas las escalas, zonas, tope diario y
--    acepta registros atrasados hasta 2 dias (antes 7).
--  * Semana del OSTRC en hora de Puerto Rico (antes UTC).
--  * player_bootstrap filtra torneos por categoria y no expone el estado
--    "pausado" de los companeros.
--  * access_token con indice unico.
-- =====================================================================

create schema if not exists angels;
grant usage on schema angels to anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- STAFF
-- ---------------------------------------------------------------------
create table angels.staff_users (
  email       text primary key,
  created_at  timestamptz not null default now()
);
alter table angels.staff_users enable row level security;
-- Sin politicas: solo se lee desde is_staff() (security definer).

create or replace function angels.is_staff()
 returns boolean
 language sql stable security definer
 set search_path to 'angels', 'pg_temp'
as $function$
  select exists (
    select 1
    from angels.staff_users s
    join auth.users u on lower(u.email) = lower(s.email)
    where u.id = auth.uid() and u.email_confirmed_at is not null
  );
$function$;

-- ---------------------------------------------------------------------
-- TABLAS
-- ---------------------------------------------------------------------
create table angels.players (
  id                 text primary key,
  name               text not null,
  nickname           text,
  team               text not null,
  number             text,
  position           text,
  phone              text,
  coach_message      text,
  injury_note        text,
  injury_updated_at  timestamptz,
  access_token       text not null default (replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','')),
  welcomed_at        timestamptz,
  status             text not null default 'activo',
  status_since       timestamptz,
  is_captain         boolean not null default false,
  created_at         timestamptz not null default now(),
  constraint players_status_chk check (status = any (array['activo','pausado'])),
  constraint players_team_chk check (team = any (array['ADCJVBoys']))
);
create unique index players_access_token_key on angels.players (access_token);

create table angels.entries (
  id             text primary key,
  player_id      text not null references angels.players(id),
  date           date not null,
  session_label  text,
  duration       integer,
  rpe            integer,
  mood           integer,
  sleep_quality  integer,
  soreness       integer,
  stress         integer,
  fatigue        integer,
  motivation     integer,
  pain_concern   integer default 0,
  pain_zones     jsonb default '[]'::jsonb,
  pain_sides     jsonb not null default '{}'::jsonb,
  notes          text,
  player_note    text,
  role_in_event  text,
  sets_played    smallint,
  created_at     timestamptz not null default now(),
  illness        smallint,
  constraint entries_session_label_chk check (session_label is null or session_label = any (array['tecnica','fisico','scrimmage','partido','recuperacion'])),
  constraint entries_recovery_pair_chk check (session_label is distinct from 'recuperacion' or ((rpe is null) = (duration is null))),
  constraint entries_rpe_chk check (rpe is null or rpe between 1 and 10),
  constraint entries_duration_chk check (duration is null or duration between 1 and 600),
  constraint entries_scales_chk check (
    (mood is null or mood between 1 and 5) and (sleep_quality is null or sleep_quality between 1 and 5) and
    (soreness is null or soreness between 1 and 5) and (stress is null or stress between 1 and 5) and
    (fatigue is null or fatigue between 1 and 5) and (motivation is null or motivation between 1 and 5)),
  constraint entries_pain_chk check (pain_concern is null or pain_concern between 0 and 3),
  constraint entries_illness_chk check (illness is null or illness between 0 and 3)
);
create index entries_player_date_idx on angels.entries (player_id, date desc);

create table angels.team_settings (
  team               text primary key,
  tournament_mode    boolean default false,
  timezone           text not null default 'America/Puerto_Rico',
  training_template  jsonb,
  practice_schedule  jsonb,   -- {"1":{"start":"19:20","end":"20:40"}}: dia (0=domingo) -> hora de la practica
  week_focus         text,
  week_focus_en      text,
  week_focus_week    date,
  constraint team_settings_team_chk check (team = any (array['ADCJVBoys']))
);

create table angels.practice_days (
  id          bigint generated by default as identity primary key,
  team        text not null,
  date        date not null,
  jump_level  text,
  created_at  timestamptz not null default now(),
  gym         boolean not null default false,
  court       boolean not null default false,
  constraint practice_days_team_date_key unique (team, date)
);

create table angels.tournaments (
  id          text primary key,
  name        text not null,
  sub         text,
  start_date  date not null,
  end_date    date not null,
  teams       text[] not null default array['ADCJVBoys'],
  color       text not null default '#51B7E4',
  weight      text not null default 'rodaje',
  kind        text not null default 'partido',
  confirmed   boolean not null default false,
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  rival       text,
  sede        text,
  jornada     integer,
  game_time   time,
  phase       text not null default 'regular',
  result      text,
  constraint tournaments_phase_check check (phase = any (array['regular','playoffs','final'])),
  constraint tournaments_sede_check  check (sede is null or sede = any (array['local','visitante'])),
  constraint tournaments_dates_chk   check (end_date >= start_date)
);

create table angels.availability (
  id          bigint generated by default as identity primary key,
  player_id   text not null references angels.players(id),
  date        date not null,
  status      text not null,
  note        text,
  created_at  timestamptz not null default now(),
  constraint availability_player_id_date_key unique (player_id, date)
);

create table angels.overuse_reports (
  id          bigint generated by default as identity primary key,
  player_id   text not null references angels.players(id),
  week_start  date not null,
  zone        text not null,
  q1          smallint not null,
  q2          smallint not null,
  q3          smallint not null,
  q4          smallint not null,
  score       smallint not null,
  created_at  timestamptz not null default now(),
  constraint overuse_reports_player_id_week_start_zone_key unique (player_id, week_start, zone)
);

create table angels.entry_edits (
  id          bigint generated by default as identity primary key,
  entry_id    text not null,
  player_id   text,
  changed_at  timestamptz not null default now(),
  changed_by  text,
  before      jsonb,
  after       jsonb
);

create sequence angels.backups_slot_seq;
create table angels.backups (
  id        bigint generated by default as identity primary key,
  slot      smallint not null unique,
  taken_at  timestamptz not null default now(),
  filas     jsonb not null,
  payload   jsonb not null
);

-- ---------------------------------------------------------------------
-- RLS: todo cerrado salvo el staff. El jugador entra solo por RPC.
-- ---------------------------------------------------------------------
alter table angels.players         enable row level security;
alter table angels.entries         enable row level security;
alter table angels.team_settings   enable row level security;
alter table angels.practice_days   enable row level security;
alter table angels.tournaments     enable row level security;
alter table angels.availability    enable row level security;
alter table angels.overuse_reports enable row level security;
alter table angels.entry_edits     enable row level security;
alter table angels.backups         enable row level security;

create policy players_staff       on angels.players         for all to authenticated using ((select angels.is_staff())) with check ((select angels.is_staff()));
create policy entries_staff       on angels.entries         for all to authenticated using ((select angels.is_staff())) with check ((select angels.is_staff()));
create policy settings_staff      on angels.team_settings   for all to authenticated using ((select angels.is_staff())) with check ((select angels.is_staff()));
create policy practice_days_staff on angels.practice_days   for all to authenticated using ((select angels.is_staff())) with check ((select angels.is_staff()));
create policy tournaments_staff   on angels.tournaments     for all to authenticated using ((select angels.is_staff())) with check ((select angels.is_staff()));
create policy availability_staff  on angels.availability    for all to authenticated using ((select angels.is_staff())) with check ((select angels.is_staff()));
create policy overuse_staff       on angels.overuse_reports for all to authenticated using ((select angels.is_staff())) with check ((select angels.is_staff()));
create policy entry_edits_staff   on angels.entry_edits     for all to authenticated using ((select angels.is_staff())) with check ((select angels.is_staff()));
create policy backups_staff       on angels.backups         for select to authenticated using ((select angels.is_staff()));

-- Tablas: el staff pasa por RLS; el rol anonimo no toca ninguna tabla.
grant select, insert, update on all tables in schema angels to authenticated, service_role;
-- Permiso de borrar para el staff: aparte, en 0016 (pendiente de Carlos).
grant usage, select on all sequences in schema angels to authenticated, service_role;
revoke all on all tables in schema angels from anon;

-- ---------------------------------------------------------------------
-- FUNCIONES
-- ---------------------------------------------------------------------
create or replace function angels.set_updated_at()
 returns trigger
 language plpgsql
 set search_path to 'angels', 'pg_temp'
as $function$
begin
  new.updated_at = now();
  return new;
end $function$;

create trigger tournaments_set_updated_at before update on angels.tournaments
  for each row execute function angels.set_updated_at();

-- Hoy en Puerto Rico (sin horario de verano: UTC-4 todo el ano).
create or replace function angels.pr_today()
 returns date
 language sql stable
 set search_path to 'angels', 'pg_temp'
as $function$ select (now() at time zone 'America/Puerto_Rico')::date $function$;

create or replace function angels.player_mark_welcomed(p_token text)
 returns jsonb
 language plpgsql security definer
 set search_path to 'angels', 'pg_temp'
as $function$
begin
  update angels.players set welcomed_at = now()
  where access_token = p_token and welcomed_at is null;
  return jsonb_build_object('ok', true);
end;
$function$;

create or replace function angels.make_backup()
 returns jsonb
 language plpgsql security definer
 set search_path to 'angels', 'pg_temp'
as $function$
declare
  v_payload jsonb;
  v_filas   jsonb;
begin
  select jsonb_build_object(
    'players',        coalesce((select jsonb_agg(to_jsonb(p) - 'access_token' - 'phone') from angels.players p), '[]'::jsonb),
    'entries',        coalesce((select jsonb_agg(to_jsonb(e)) from angels.entries e), '[]'::jsonb),
    'availability',   coalesce((select jsonb_agg(to_jsonb(a)) from angels.availability a), '[]'::jsonb),
    'overuse',        coalesce((select jsonb_agg(to_jsonb(o)) from angels.overuse_reports o), '[]'::jsonb),
    'tournaments',    coalesce((select jsonb_agg(to_jsonb(t)) from angels.tournaments t), '[]'::jsonb),
    'practice_days',  coalesce((select jsonb_agg(to_jsonb(d)) from angels.practice_days d), '[]'::jsonb),
    'team_settings',  coalesce((select jsonb_agg(to_jsonb(s)) from angels.team_settings s), '[]'::jsonb)
  ) into v_payload;

  select jsonb_build_object(
    'players',      (select count(*) from angels.players),
    'entries',      (select count(*) from angels.entries),
    'availability', (select count(*) from angels.availability),
    'overuse',      (select count(*) from angels.overuse_reports)
  ) into v_filas;

  -- Se guardan 10 copias que se van rotando: la nueva ocupa el lugar de la
  -- mas vieja (sin borrar filas).
  insert into angels.backups (slot, filas, payload)
  values ((nextval('angels.backups_slot_seq') % 10)::smallint, v_filas, v_payload)
  on conflict (slot) do update
    set taken_at = now(), filas = excluded.filas, payload = excluded.payload;
  return v_filas;
end;
$function$;

create or replace function angels.player_bootstrap(p_token text)
 returns jsonb
 language plpgsql security definer
 set search_path to 'angels', 'pg_temp'
as $function$
declare
  v_player angels.players%rowtype;
  v_result jsonb;
begin
  if p_token is null or length(p_token) < 32 then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  select * into v_player from angels.players where access_token = p_token;
  if not found then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;

  select jsonb_build_object(
    'player', (to_jsonb(v_player) - 'access_token' - 'phone'),
    'entries', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.date desc)
      from angels.entries e where e.player_id = v_player.id
    ), '[]'::jsonb),
    -- Companeros activos de su categoria. Del companero solo se sabe nombre,
    -- dorsal y posicion; nunca su estado ni nada de salud.
    'roster', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'nickname', p.nickname, 'team', p.team,
        'number', p.number, 'position', p.position,
        'status', case when p.id = v_player.id then p.status else 'activo' end
      ) order by p.name)
      from angels.players p
      where p.team = v_player.team and (p.status = 'activo' or p.id = v_player.id)
    ), '[]'::jsonb),
    'checkins', coalesce((
      select jsonb_agg(jsonb_build_object('player_id', c.player_id, 'date', c.date))
      from (
        select distinct e2.player_id, e2.date
        from angels.entries e2
        join angels.players p2 on p2.id = e2.player_id
        where p2.team = v_player.team and (p2.status = 'activo' or p2.id = v_player.id)
          and e2.date >= pr_today() - 60
      ) c
    ), '[]'::jsonb),
    'practice_days', coalesce((
      select jsonb_agg(jsonb_build_object(
        'team', d.team, 'date', d.date, 'gym', d.gym, 'court', d.court, 'jump_level', d.jump_level))
      from angels.practice_days d
      where d.team = v_player.team and d.date >= pr_today() - 220
    ), '[]'::jsonb),
    'tournaments', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.start_date)
      from angels.tournaments t where v_player.team = any(t.teams)
    ), '[]'::jsonb),
    'team_settings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'team', s.team, 'tournament_mode', s.tournament_mode, 'timezone', s.timezone,
        'training_template', s.training_template, 'practice_schedule', s.practice_schedule,
        'week_focus', s.week_focus, 'week_focus_en', s.week_focus_en, 'week_focus_week', s.week_focus_week))
      from angels.team_settings s where s.team = v_player.team
    ), '[]'::jsonb),
    'overuse', coalesce((
      select jsonb_agg(jsonb_build_object('week_start', o.week_start, 'zone', o.zone, 'score', o.score))
      from angels.overuse_reports o
      where o.player_id = v_player.id and o.week_start >= pr_today() - 120
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

create or replace function angels.player_submit_overuse(p_token text, p_zone text, p_q1 integer, p_q2 integer, p_q3 integer, p_q4 integer)
 returns jsonb
 language plpgsql security definer
 set search_path to 'angels', 'pg_temp'
as $function$
declare
  v_player angels.players%rowtype;
  v_week   date;
  v_score  int;
  f14      int[] := array[0, 8, 17, 25];
  f23      int[] := array[0, 6, 13, 25];
begin
  select * into v_player from angels.players where access_token = p_token;
  if not found then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  if v_player.status = 'pausado' then
    raise exception 'Tu perfil esta en pausa. Habla con el coach.' using errcode = '28000';
  end if;
  if p_zone is null or length(trim(p_zone)) = 0 then
    raise exception 'Falta la zona';
  end if;
  if p_q1 not between 0 and 3 or p_q2 not between 0 and 3
     or p_q3 not between 0 and 3 or p_q4 not between 0 and 3 then
    raise exception 'Respuesta fuera de rango';
  end if;

  -- Lunes de la semana en hora de Puerto Rico (antes se calculaba en UTC y
  -- lo enviado despues de las 8pm caia en la semana siguiente).
  v_week  := date_trunc('week', pr_today())::date;
  v_score := f14[p_q1 + 1] + f23[p_q2 + 1] + f23[p_q3 + 1] + f14[p_q4 + 1];

  insert into angels.overuse_reports (player_id, week_start, zone, q1, q2, q3, q4, score)
  values (v_player.id, v_week, left(trim(p_zone), 40), p_q1, p_q2, p_q3, p_q4, v_score)
  on conflict (player_id, week_start, zone) do update
    set q1 = excluded.q1, q2 = excluded.q2, q3 = excluded.q3, q4 = excluded.q4,
        score = excluded.score, created_at = now();

  return jsonb_build_object('ok', true, 'score', v_score, 'week_start', v_week);
end;
$function$;

create or replace function angels.player_submit_checkin(p_token text, p_entry jsonb, p_replace boolean default false)
 returns jsonb
 language plpgsql security definer
 set search_path to 'angels', 'pg_temp'
as $function$
declare
  v_player   angels.players%rowtype;
  v_id       text;
  v_date     date;
  v_hoy      date := pr_today();
  v_sesion   text;
  v_rpe      int;
  v_dur      int;
  v_borradas int := 0;
  v_existen  int;
  v_zones    jsonb;
  v_sides    jsonb;
  v_k        text;
  v_v        jsonb;
  v_rol      text;
  v_sets     int;
  v_old      text;
begin
  select * into v_player from angels.players where access_token = p_token;
  if not found then
    raise exception 'Enlace no valido' using errcode = '28000';
  end if;
  if v_player.status = 'pausado' then
    raise exception 'Tu perfil esta en pausa. Habla con el coach.' using errcode = '28000';
  end if;

  v_id     := coalesce(nullif(p_entry->>'id', ''), gen_random_uuid()::text);
  if length(v_id) > 80 then raise exception 'Registro no valido'; end if;
  v_date   := coalesce((p_entry->>'date')::date, v_hoy);
  v_sesion := nullif(p_entry->>'session_label', '');

  if v_date > v_hoy + 1 then raise exception 'No se permiten fechas futuras'; end if;
  -- El jugador registra por su cuenta hasta 2 dias atras. Mas atras lo
  -- corrige el coach desde su panel.
  if v_date < v_hoy - 2 then raise exception 'Solo puedes registrar hasta 2 dias atras. Para fechas anteriores, habla con el coach.'; end if;

  v_rpe := nullif(p_entry->>'rpe', '')::int;
  v_dur := nullif(p_entry->>'duration', '')::int;
  if v_sesion = 'recuperacion' then
    if (v_rpe is null) <> (v_dur is null) then
      raise exception 'Recuperacion activa: RPE y duracion van juntos';
    end if;
    if v_rpe is not null and (v_rpe < 1 or v_rpe > 10) then raise exception 'RPE fuera de rango'; end if;
    if v_dur is not null and (v_dur < 1 or v_dur > 240) then raise exception 'Duracion fuera de rango'; end if;
  else
    if v_rpe is null or v_rpe < 1 or v_rpe > 10 then raise exception 'RPE fuera de rango'; end if;
    if v_dur is null or v_dur < 1 or v_dur > 600 then raise exception 'Duracion fuera de rango'; end if;
  end if;

  -- Escalas de bienestar 1-5; dolor y enfermedad 0-3.
  if exists (
    select 1 from unnest(array['mood','sleep_quality','soreness','stress','fatigue','motivation']) k
    where nullif(p_entry->>k, '') is not null and (p_entry->>k)::int not between 1 and 5
  ) then raise exception 'Respuesta de bienestar fuera de rango'; end if;
  if nullif(p_entry->>'pain_concern','') is not null and (p_entry->>'pain_concern')::int not between 0 and 3 then
    raise exception 'Nivel de dolor fuera de rango'; end if;
  if nullif(p_entry->>'illness','') is not null and (p_entry->>'illness')::int not between 0 and 3 then
    raise exception 'Nivel de enfermedad fuera de rango'; end if;

  v_rol := nullif(p_entry->>'role_in_event', '');
  if v_rol is not null and v_rol <> all (array['titular','reserva','mixto']) then
    raise exception 'Rol no valido'; end if;
  v_sets := nullif(p_entry->>'sets_played', '')::int;
  if v_sets is not null and (v_sets < 0 or v_sets > 15) then raise exception 'Sets fuera de rango'; end if;

  v_zones := coalesce(p_entry->'pain_zones', '[]'::jsonb);
  if jsonb_typeof(v_zones) <> 'array' or jsonb_array_length(v_zones) > 12 then
    raise exception 'Zonas de dolor no validas'; end if;
  if exists (select 1 from jsonb_array_elements(v_zones) z
             where jsonb_typeof(z) <> 'string' or length(z #>> '{}') > 40) then
    raise exception 'Zonas de dolor no validas'; end if;
  v_sides := coalesce(p_entry->'pain_sides', '{}'::jsonb);
  if jsonb_typeof(v_sides) <> 'object' then raise exception 'Lados de dolor no validos'; end if;
  for v_k, v_v in select key, value from jsonb_each(v_sides) loop
    if length(v_k) > 40 or (v_v #>> '{}') <> all (array['izq','der','ambos']) then
      raise exception 'Lados de dolor no validos'; end if;
  end loop;

  -- Corregir: el registro de ese dia y sesion se actualiza en su lugar.
  if p_replace then
    select e.id into v_old from angels.entries e
    where e.player_id = v_player.id and e.date = v_date
      and coalesce(e.session_label,'') = coalesce(v_sesion,'')
    order by e.created_at desc limit 1;
    if v_old is not null then v_id := v_old; v_borradas := 1; end if;
  end if;

  -- Tope en el servidor: el app permite hasta 2 registros de entrenamiento al
  -- dia; 3 deja margen para partido o recuperacion y corta el abuso.
  select count(*) into v_existen from angels.entries
  where player_id = v_player.id and date = v_date and id <> v_id;
  if v_existen >= 3 then
    raise exception 'Ya tienes los registros de ese dia. Si hay un error, habla con el coach.';
  end if;

  insert into angels.entries (
    id, player_id, date, session_label, role_in_event, sets_played,
    duration, rpe, mood, sleep_quality, soreness, stress, fatigue, motivation,
    pain_concern, pain_zones, pain_sides, illness, notes, player_note
  ) values (
    v_id, v_player.id, v_date, v_sesion, v_rol, v_sets,
    v_dur, v_rpe,
    nullif(p_entry->>'mood','')::int,
    nullif(p_entry->>'sleep_quality','')::int,
    nullif(p_entry->>'soreness','')::int,
    nullif(p_entry->>'stress','')::int,
    nullif(p_entry->>'fatigue','')::int,
    nullif(p_entry->>'motivation','')::int,
    coalesce(nullif(p_entry->>'pain_concern','')::int, 0),
    v_zones, v_sides,
    nullif(p_entry->>'illness','')::int,
    left(coalesce(p_entry->>'notes', ''), 1000),
    left(nullif(p_entry->>'player_note', ''), 1000)
  )
  on conflict (id) do update set
    session_label = excluded.session_label, role_in_event = excluded.role_in_event,
    sets_played = excluded.sets_played, duration = excluded.duration, rpe = excluded.rpe,
    mood = excluded.mood, sleep_quality = excluded.sleep_quality, soreness = excluded.soreness,
    stress = excluded.stress, fatigue = excluded.fatigue, motivation = excluded.motivation,
    pain_concern = excluded.pain_concern, pain_zones = excluded.pain_zones,
    pain_sides = excluded.pain_sides, illness = excluded.illness, notes = excluded.notes,
    player_note = excluded.player_note
  where p_replace and angels.entries.player_id = v_player.id;

  return jsonb_build_object('ok', true, 'id', v_id, 'reemplazadas', v_borradas);
end;
$function$;

-- ---------------------------------------------------------------------
-- PERMISOS DE FUNCIONES: nada abierto por defecto.
-- ---------------------------------------------------------------------
revoke execute on all functions in schema angels from public, anon, authenticated;
grant execute on all functions in schema angels to service_role;
grant execute on function angels.is_staff() to authenticated;
grant execute on function angels.player_bootstrap(text) to anon, authenticated;
grant execute on function angels.player_mark_welcomed(text) to anon, authenticated;
grant execute on function angels.player_submit_checkin(text, jsonb, boolean) to anon, authenticated;
grant execute on function angels.player_submit_overuse(text, text, integer, integer, integer, integer) to anon, authenticated;
alter default privileges for role postgres in schema angels revoke execute on functions from public, anon, authenticated;
