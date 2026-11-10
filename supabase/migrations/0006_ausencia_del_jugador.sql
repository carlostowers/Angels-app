-- =====================================================================
-- ANGELS (derivado de STATION v2.5.1) - 0006 AUSENCIA MARCADA POR EL JUGADOR
--  * El jugador marca "Me ausente" desde su check-in, con un motivo
--    (escuela, enfermo, lesion, otro). Se guarda en angels.availability,
--    la misma tabla de la disponibilidad que marca el staff:
--      lesion            -> status 'lesionado'
--      escuela/enfermo/otro -> status 'ninguno'
--    Los avisos (reminders_due) y la falta por semana sin check-in
--    (checkin_suggestions_for) ya excluyen esos dos estados: no cambian.
--  * Columnas nuevas: reason (motivo) y source (staff o jugador).
--  * player_mark_absent: unica via del jugador para escribir aqui.
--    Valida token, estado, motivo, fecha (hoy o hasta 2 dias atras),
--    que ese dia hubo practica o partido y que no haya registrado ya una
--    sesion. No pisa lo que haya marcado el staff.
--  * Si despues registra una sesion de ese dia, el registro gana: un
--    trigger cambia la ausencia a completo que el mismo jugador habia marcado.
--  * player_bootstrap devuelve las ausencias: las suyas con motivo y las
--    de sus companeros solo como "ausente", sin motivo (dato de salud de
--    un menor).
-- =====================================================================

alter table angels.availability
  add column if not exists reason text,
  add column if not exists source text not null default 'staff';

alter table angels.availability add constraint availability_status_check
  check (status in ('completo','parcial','ninguno','lesionado'));

alter table angels.availability add constraint availability_reason_check
  check (reason is null or reason in ('escuela','enfermo','lesion','otro'));

alter table angels.availability add constraint availability_source_check
  check (source in ('staff','jugador'));

-- ---------------------------------------------------------------------
-- El jugador marca que se ausento
-- ---------------------------------------------------------------------
create or replace function angels.player_mark_absent(p_token text, p_date date, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_player angels.players%rowtype;
  v_hoy    date := pr_today();
  v_date   date := coalesce(p_date, pr_today());
  v_status text;
  v_prev   angels.availability%rowtype;
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
  if p_reason is null or p_reason <> all (array['escuela','enfermo','lesion','otro']) then
    raise exception 'Motivo no valido';
  end if;
  if v_date > v_hoy then
    raise exception 'No se permiten fechas futuras';
  end if;
  if v_date < v_hoy - 2 then
    raise exception 'Solo puedes marcar hasta 2 dias atras. Para fechas anteriores, habla con el coach.';
  end if;
  if v_date < date '2026-11-02' then
    raise exception 'Fecha no valida';
  end if;
  if not angels.team_has_session(v_player.team, v_date) then
    raise exception 'Ese dia no hubo practica ni partido';
  end if;
  if exists (select 1 from angels.entries e where e.player_id = v_player.id and e.date = v_date) then
    raise exception 'Ya registraste una sesion ese dia';
  end if;
  select * into v_prev from angels.availability a
   where a.player_id = v_player.id and a.date = v_date;
  if found and v_prev.source = 'staff' then
    raise exception 'El coach ya marco tu asistencia de ese dia';
  end if;

  v_status := case when p_reason = 'lesion' then 'lesionado' else 'ninguno' end;
  insert into angels.availability (player_id, date, status, reason, source, note)
  values (v_player.id, v_date, v_status, p_reason, 'jugador', null)
  on conflict (player_id, date) do update
     set status = excluded.status, reason = excluded.reason,
         source = 'jugador', note = null, created_at = now();

  return jsonb_build_object('ok', true, 'date', v_date, 'status', v_status, 'reason', p_reason);
end;
$$;
revoke all on function angels.player_mark_absent(text, date, text) from public;
grant execute on function angels.player_mark_absent(text, date, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Si registra una sesion de ese dia, el registro gana
-- ---------------------------------------------------------------------
create or replace function angels.entry_clears_player_absence()
returns trigger
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
begin
  update angels.availability a
     set status = 'completo', reason = null
   where a.player_id = new.player_id and a.date = new.date and a.source = 'jugador';
  return new;
end;
$$;
revoke all on function angels.entry_clears_player_absence() from public, anon, authenticated;

create trigger entries_clear_player_absence
  after insert or update of date on angels.entries
  for each row execute function angels.entry_clears_player_absence();

-- ---------------------------------------------------------------------
-- player_bootstrap: igual que antes, mas 'absences'
-- ---------------------------------------------------------------------
create or replace function angels.player_bootstrap(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'angels', 'pg_temp'
as $$
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
    -- Las propias, completas (sin la nota del staff). Las de los companeros
    -- solo dicen que ese dia no estuvo: ni el motivo ni si fue lesion.
    'absences', coalesce((
      select jsonb_agg(jsonb_build_object(
        'player_id', a.player_id, 'date', a.date,
        'status', case when a.player_id = v_player.id then a.status else 'ninguno' end,
        'reason', case when a.player_id = v_player.id then a.reason else null end,
        'source', case when a.player_id = v_player.id then a.source else null end))
      from angels.availability a
      join angels.players p3 on p3.id = a.player_id
      where p3.team = v_player.team and (p3.status = 'activo' or p3.id = v_player.id)
        and a.date >= pr_today() - 60
        and (a.player_id = v_player.id or a.status in ('ninguno','lesionado'))
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
$$;
