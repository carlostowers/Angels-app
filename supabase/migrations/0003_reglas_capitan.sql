-- =====================================================================
-- ANGELS - 0003 DIAS DE SESION
-- Angels no usa reglas, faltas, capitan ni reconocimiento semanal (decision
-- de Carlos, 2026-11-10): no se crean esas tablas ni funciones. Solo queda
-- team_has_session, que usan los avisos.
-- =====================================================================

create or replace function angels.team_has_session(p_team text, p_date date)
 returns boolean
 language sql stable security definer
 set search_path to 'angels', 'pg_temp'
as $function$
  select coalesce(
    (select (d.gym or d.court) from angels.practice_days d where d.team = p_team and d.date = p_date),
    (select coalesce((s.training_template -> (extract(dow from p_date)::int::text) ->> 'gym')::boolean, false)
         or coalesce((s.training_template -> (extract(dow from p_date)::int::text) ->> 'court')::boolean, false)
     from angels.team_settings s where s.team = p_team),
    false)
  or exists (
    select 1 from angels.tournaments t
    where p_team = any(t.teams)
      and p_date between t.start_date and t.end_date
      and (t.kind = 'partido' or (t.end_date - t.start_date) <= 3)
  );
$function$;
revoke all on function angels.team_has_session(text, date) from public, anon, authenticated;
grant execute on function angels.team_has_session(text, date) to service_role;
