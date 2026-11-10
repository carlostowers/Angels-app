-- =====================================================================
-- ANGELS (derivado de STATION v2.5.1) - 0007 PLAN DE SESION Y UMBRALES (v2.1.0)
--  * practice_days: el staff planifica cada sesion con intencion de RPE,
--    duracion prevista y una nota de enfoque que el jugador ve en Hoy.
--    La carga planificada (plan_rpe x plan_min) se compara con la real
--    en el Microciclo. Todo opcional: sin plan, el dia se comporta igual
--    que antes.
--  * team_settings.umbrales: los cortes que usa el panel del staff
--    (señales z, linea base minima, subida semanal que avisa, factor de
--    salto por posicion), editables desde Reglas y umbrales, con la fecha
--    desde la que aplican. Sin fila o sin clave, la app usa sus valores
--    por defecto documentados en PROMPT_2_design_v2.md.
--  * player_bootstrap devuelve ademas el plan de cada dia (rpe, minutos,
--    nota). Los umbrales no se envian al jugador: nunca ve numeros.
-- =====================================================================

alter table angels.practice_days
  add column if not exists plan_rpe  smallint,
  add column if not exists plan_min  smallint,
  add column if not exists plan_nota text;

alter table angels.practice_days add constraint practice_days_plan_chk check (
  (plan_rpe is null or plan_rpe between 1 and 10) and
  (plan_min is null or plan_min between 1 and 600) and
  (plan_nota is null or length(plan_nota) <= 140)
);

alter table angels.team_settings
  add column if not exists umbrales jsonb;

comment on column angels.team_settings.umbrales is
  'Cortes del panel del staff. Claves: z_leve (-1.0), z_grave (-1.5), base_n (5), abs_max (2), subida_pct (30), salto {MH:1.2,OP:1.1,OH:1.0,S:0.8,L:0.3,DS:0.3}, vigente_desde (fecha ISO). Sin fila o sin clave aplica el valor por defecto de la app.';

-- ---------------------------------------------------------------------
-- player_bootstrap: igual que 0006, mas plan_rpe, plan_min y plan_nota
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
        'team', d.team, 'date', d.date, 'gym', d.gym, 'court', d.court, 'jump_level', d.jump_level,
        'plan_rpe', d.plan_rpe, 'plan_min', d.plan_min, 'plan_nota', d.plan_nota))
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
