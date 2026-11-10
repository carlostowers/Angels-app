-- =====================================================================
-- ANGELS - 0015 TAREAS PROGRAMADAS DE AVISOS
-- Se aplica despues de publicar la funcion angels-push.
--  * angels-recordatorios: cada 15 minutos (avisos del check-in y del staff).
--  * angels-mensajes: cada 5 minutos, solo si hay un mensaje programado vencido.
-- =====================================================================

select cron.schedule(
  'angels-recordatorios',
  '*/15 * * * *',
  $cron$
  select net.http_post(
    url := 'https://qagvxlenrojmgzjoywzm.supabase.co/functions/v1/angels-push',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-cron-secret', (select cron_secret from angels.push_config where id = 1)),
    body := '{}'::jsonb,
    timeout_milliseconds := 20000
  );
  $cron$
);

select cron.schedule(
  'angels-mensajes',
  '*/5 * * * *',
  $cron$
  select net.http_post(
    url := 'https://qagvxlenrojmgzjoywzm.supabase.co/functions/v1/angels-push',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-cron-secret', (select cron_secret from angels.push_config where id = 1)),
    body := '{"mensajes": true}'::jsonb,
    timeout_milliseconds := 30000
  )
  where exists (select 1 from angels.staff_messages
                 where (status = 'programado' and send_at <= now())
                    or (status = 'enviando' and claimed_at < now() - interval '15 minutes'));
  $cron$
);
