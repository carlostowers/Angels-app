-- =====================================================================
-- ANGELS - 0030 Retencion del historial de uso
-- ---------------------------------------------------------------------
-- Carlos (16 nov. 2026): el historial de uso de Angels se borra con la
-- misma regla de STATION, temporada + 12 meses. La temporada empieza el
-- 1 de agosto; se borra lo anterior al 1 de agosto de la temporada pasada.
-- Corre los lunes 09:25 UTC (05:25 en Puerto Rico) con pg_cron. Solo toca
-- angels.app_events; app_presence es una fila por jugador y no crece.
-- La funcion no se puede llamar por la API: solo la ejecuta el cron.
-- =====================================================================

create or replace function angels.purgar_uso_vencido()
returns jsonb
language plpgsql
set search_path to 'angels', 'pg_temp'
as $$
declare
  v_hoy   date := (now() at time zone 'America/Puerto_Rico')::date;
  v_corte date;
  n       integer := 0;
begin
  v_corte := (make_date(extract(year from v_hoy)::int
                        - case when extract(month from v_hoy) < 8 then 1 else 0 end, 8, 1)
              - interval '12 months')::date;
  delete from angels.app_events where (at at time zone 'America/Puerto_Rico')::date < v_corte;
  get diagnostics n = row_count;
  return jsonb_build_object('corte', v_corte, 'app_events', n);
end;
$$;
comment on function angels.purgar_uso_vencido() is
  'Borra el historial de uso anterior a la temporada pasada (temporada + 12 meses). La ejecuta pg_cron (angels-retencion-uso), no la API.';
revoke all on function angels.purgar_uso_vencido() from public, anon, authenticated;

do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'angels-retencion-uso';
  perform cron.schedule('angels-retencion-uso', '25 9 * * 1', 'select angels.purgar_uso_vencido();');
end
$$;
