-- =====================================================================
-- ANGELS - 0017 Sincronizacion al publicar v4.0.0 (10 nov. 2026)
-- Misma copia de datos de 0014 (sin la creacion de la tabla growth),
-- corrida justo despues de publicar para traer lo que los jugadores
-- registraron en la app vieja (esquema public). No borra nada.
-- =====================================================================

-- Jugadores
insert into angels.players (id, name, team, number, position, phone, coach_message,
                            injury_note, injury_updated_at, access_token, welcomed_at)
select id, name, team, number, position, phone, coach_message,
       injury_note, injury_updated_at, access_token, welcomed_at
from public.players
on conflict (id) do update set
  name = excluded.name, team = excluded.team, number = excluded.number,
  position = excluded.position, phone = excluded.phone,
  coach_message = excluded.coach_message, injury_note = excluded.injury_note,
  injury_updated_at = excluded.injury_updated_at, access_token = excluded.access_token,
  welcomed_at = coalesce(angels.players.welcomed_at, excluded.welcomed_at);

-- Configuracion del equipo
insert into angels.team_settings (team, tournament_mode, timezone, week_focus, week_focus_week)
select team, tournament_mode, timezone, week_focus, week_focus_week
from public.team_settings
on conflict (team) do update set
  tournament_mode = excluded.tournament_mode, timezone = excluded.timezone,
  week_focus = excluded.week_focus, week_focus_week = excluded.week_focus_week;

-- Registros (check-ins)
insert into angels.entries (id, player_id, date, session_label, duration, rpe, mood,
  sleep_quality, soreness, stress, fatigue, motivation, pain_concern, pain_zones,
  notes, player_note, role_in_event, sets_played, created_at, pain_sides, illness)
select id, player_id, date, session_label, duration, rpe, mood,
  sleep_quality, soreness, stress, fatigue, motivation, pain_concern, pain_zones,
  notes, player_note, role_in_event, sets_played, created_at, pain_sides, illness
from public.entries
on conflict (id) do update set
  date = excluded.date, session_label = excluded.session_label, duration = excluded.duration,
  rpe = excluded.rpe, mood = excluded.mood, sleep_quality = excluded.sleep_quality,
  soreness = excluded.soreness, stress = excluded.stress, fatigue = excluded.fatigue,
  motivation = excluded.motivation, pain_concern = excluded.pain_concern,
  pain_zones = excluded.pain_zones, notes = excluded.notes, player_note = excluded.player_note,
  role_in_event = excluded.role_in_event, sets_played = excluded.sets_played,
  pain_sides = excluded.pain_sides, illness = excluded.illness;

-- Dias de practica (los activos)
insert into angels.practice_days (team, date, jump_level, court, created_at)
select team, date, jump_level, true, created_at
from public.practice_days
where active
on conflict (team, date) do update set jump_level = excluded.jump_level, court = true;

-- Torneos
insert into angels.tournaments (id, name, sub, start_date, end_date, teams, color, weight,
  kind, confirmed, notes, created_at, updated_at)
select id, name, sub, start_date, end_date, teams, color, weight,
  kind, confirmed, notes, created_at, updated_at
from public.tournaments
on conflict (id) do update set
  name = excluded.name, sub = excluded.sub, start_date = excluded.start_date,
  end_date = excluded.end_date, teams = excluded.teams, color = excluded.color,
  weight = excluded.weight, confirmed = excluded.confirmed, notes = excluded.notes;

-- Juegos de Buzzer Beater como partidos individuales
update angels.tournaments set kind = 'partido', game_time = '16:40', rival = 'La Salle',
  sub = 'Cancha 3', phase = 'playoffs', name = 'Buzzer Beater'
  where id = 'bb26-juego1-1113';
update angels.tournaments set kind = 'partido', game_time = '09:30', rival = 'St. Francis o Pentecostal',
  sub = 'Cancha 1', phase = 'playoffs', name = 'Buzzer Beater'
  where id = 'bb26-juego2-1117';
update angels.tournaments set kind = 'partido', game_time = '19:40', rival = 'Por definir',
  sub = 'Cancha 1', phase = 'playoffs', name = 'Buzzer Beater · Cuartos de final'
  where id = 'bb26-cuartos-1120';
update angels.tournaments set kind = 'partido', game_time = '20:00', rival = 'Por definir',
  sub = 'Cancha 2', phase = 'playoffs', name = 'Buzzer Beater · Semifinal'
  where id = 'bb26-semi-1121';
update angels.tournaments set kind = 'partido', game_time = '17:00', rival = 'Por definir',
  sub = 'Cancha central', phase = 'final', name = 'Buzzer Beater · Final'
  where id = 'bb26-final-1122';

-- Disponibilidad
insert into angels.availability (player_id, date, status, note, created_at)
select player_id, date, status, note, created_at
from public.availability
on conflict (player_id, date) do update set status = excluded.status, note = excluded.note;

-- Estatura
insert into angels.growth (player_id, date, height_cm, created_at)
select g.player_id, g.date, g.height_cm, g.created_at
from public.growth g
where not exists (select 1 from angels.growth x
                  where x.player_id = g.player_id and x.date = g.date and x.height_cm = g.height_cm);

-- OSTRC-O
insert into angels.overuse_reports (player_id, week_start, zone, q1, q2, q3, q4, score, created_at)
select player_id, week_start, zone, q1, q2, q3, q4, score, created_at
from public.overuse_reports
on conflict (player_id, week_start, zone) do update set
  q1 = excluded.q1, q2 = excluded.q2, q3 = excluded.q3, q4 = excluded.q4, score = excluded.score;

-- Historial de correcciones
insert into angels.entry_edits (entry_id, player_id, changed_at, changed_by, before, after)
select e.entry_id, e.player_id, e.changed_at, e.changed_by, e.before, e.after
from public.entry_edits e
where not exists (select 1 from angels.entry_edits x
                  where x.entry_id = e.entry_id and x.changed_at = e.changed_at);
