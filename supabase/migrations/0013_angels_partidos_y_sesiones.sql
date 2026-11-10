-- =====================================================================
-- ANGELS - 0013 PARTIDOS INDIVIDUALES Y DIAS DE SESION
-- En Angels un torneo puede durar semanas (Buzzer Beater: 4 al 22 de
-- noviembre) y los juegos se cargan aparte, uno por fila (kind 'partido',
-- con game_time). Para que los avisos no salgan todos los dias del rango:
--  * team_has_session: cuenta el dia de un partido, o cualquier dia de un
--    torneo corto (4 dias o menos). Un torneo largo sin partidos ese dia
--    no cuenta; la practica sigue contando como siempre.
--  * session_end_at: si ese dia hay partido con hora, la sesion termina
--    2 horas despues del ultimo partido; si es dia de torneo corto, 7:30pm;
--    si no, la hora del horario de practica (9pm por defecto).
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

create or replace function angels.session_end_at(p_team text, p_date date)
 returns timestamp
 language sql stable security definer
 set search_path to 'angels', 'pg_temp'
as $function$
  select coalesce(
    (select p_date + max(t.game_time) + interval '2 hours'
       from angels.tournaments t
      where p_team = any(t.teams) and t.kind = 'partido'
        and p_date between t.start_date and t.end_date and t.game_time is not null
     having max(t.game_time) is not null),
    case
      when exists (select 1 from angels.tournaments t
                    where p_team = any(t.teams) and p_date between t.start_date and t.end_date
                      and (t.end_date - t.start_date) <= 3)
        then p_date + time '19:30'
      else p_date + coalesce((select (s.practice_schedule -> (extract(dow from p_date)::int::text) ->> 'end')::time
                              from angels.team_settings s where s.team = p_team), time '21:00')
    end);
$function$;

revoke all on function angels.team_has_session(text, date) from public, anon, authenticated;
revoke all on function angels.session_end_at(text, date) from public, anon, authenticated;
grant execute on function angels.team_has_session(text, date) to service_role;
grant execute on function angels.session_end_at(text, date) to service_role;
