-- 0022: cierra las funciones de la app anterior de Angels (esquema public).
--
-- Angels v4 solo usa el esquema angels. El esquema public quedo congelado
-- como respaldo el 2026-11-10, pero sus funciones seguian abiertas para
-- anon y authenticated: un enlace viejo de jugador todavia podia leer o
-- escribir en las tablas congeladas.
--
-- Esta migracion solo quita permisos de ejecucion. No borra funciones,
-- tablas ni datos. El cron respaldo_semanal corre como postgres y sigue
-- funcionando. service_role conserva el permiso.
--
-- Para revertir: grant execute on function ... to anon, authenticated;
-- (make_backup solo lo tenia authenticated).

revoke execute on function public.player_bootstrap(text) from public, anon, authenticated;
revoke execute on function public.player_mark_welcomed(text) from public, anon, authenticated;
revoke execute on function public.player_submit_checkin(text, jsonb, boolean) from public, anon, authenticated;
revoke execute on function public.player_submit_overuse(text, text, integer, integer, integer, integer) from public, anon, authenticated;
revoke execute on function public.make_backup() from public, anon, authenticated;
