-- =====================================================================
-- 0020 · Aviso de check-in de Angels a las 6:30 p.m.
-- ---------------------------------------------------------------------
-- Angels no siempre tiene horario de práctica en team_settings, así que
-- session_end_at usaba 9:00 p.m. por defecto y el aviso salía a las
-- 9:30 p.m. Ahora el fin por defecto de la práctica es 6:00 p.m. y el
-- aviso (30 minutos después) sale a las 6:30 p.m., hora de Puerto Rico.
-- Lo demás no cambia: si hay horario del día en practice_schedule, manda
-- ese; en partidos con hora, fin = hora del partido + 2 h; en torneos
-- cortos, 7:30 p.m.
-- El cron angels-recordatorios pasa de cada 15 a cada 5 minutos para que
-- el aviso salga a la hora exacta. reminder_log evita duplicados.
-- =====================================================================

create or replace function angels.session_end_at(p_team text, p_date date)
returns timestamp without time zone
language sql
stable
security definer
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
                              from angels.team_settings s where s.team = p_team), time '18:00')
    end);
$function$;

select cron.alter_job(
  (select jobid from cron.job where jobname = 'angels-recordatorios'),
  schedule := '*/5 * * * *'
);
