-- =====================================================================
-- ANGELS (derivado de STATION v2.5.1) - 0005 CONFIGURACION DE PUSH Y TAREAS PROGRAMADAS
--  * push_config: una sola fila. El secreto del cron se genera aqui, en el
--    servidor; las llaves VAPID las genera la funcion angels-push la
--    primera vez que corre. Ningun valor secreto pasa por el codigo ni por
--    el repositorio. Solo service_role puede leer la tabla.
--  * Cada 15 minutos pg_cron llama a angels-push (recordatorios).
--  * Todos los dias a las 4am de Puerto Rico: angels.make_backup().
-- =====================================================================

create extension if not exists pg_net;

create table angels.push_config (
  id            int primary key default 1,
  vapid_public  text,
  vapid_private text,
  cron_secret   text not null default encode(extensions.gen_random_bytes(32), 'hex'),
  updated_at    timestamptz not null default now(),
  constraint push_config_una_fila check (id = 1)
);
alter table angels.push_config enable row level security;
revoke all on angels.push_config from anon, authenticated;
grant select, insert, update on angels.push_config to service_role;
insert into angels.push_config (id) values (1) on conflict do nothing;

-- (cron de recordatorios en 0015, se activa con la funcion angels-push)

select cron.schedule('angels-respaldo-diario', '0 8 * * *', $cron$ select angels.make_backup(); $cron$);
