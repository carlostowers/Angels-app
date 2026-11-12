# Angels - base de datos (esquema `angels`)

Derivada de Station v2.5.1, en el mismo proyecto Supabase, aislada en su propio esquema.
El esquema `public` (app actual) no se toca: queda como respaldo.

Aplicadas el 2026-11-10, en este orden: 0001, 0003, 0004, 0005, 0006, 0007, 0009, 0010, 0011, 0012, 0013, 0014, 0015, 0016, 0017.
Ninguna migracion borra nada (sin DROP, DELETE ni TRUNCATE).
v4.0.0 publicada en angelsapp.thegriit.com el 2026-11-10; 0017 copio lo ultimo de `public` al publicar.
El esquema `angels` ya esta expuesto en Supabase.

0016 (permiso de borrar para el staff) aplicada con el permiso de Carlos.
- No hay 0002 (no aplica) ni 0008 (retencion: borraba datos viejos; Angels no la usa).

0018 (BAREBORU by VOLEII, tercer juego) aplicada el 2026-11-11: agrega `bareboru` a los records, tops y borrado, valida el partido 3v3 en el servidor y crea `game_plays` (registro anonimo de partidas, RLS, lectura solo staff). Sin DROP de tablas, DELETE ni TRUNCATE.
El uno contra uno en linea usa las funciones `bb_room_create`, `bb_room_join`, `bb_room_result` y `bb_record` del esquema `station` (migracion 0015 de STATION), que validan el enlace del jugador de Angels contra `angels.players`. En el esquema `angels` no hay tablas de salas.
El archivo `juegos/bareboru/index.html` es el mismo de STATION: en este dominio usa los colores, el esquema y el top de Angels. No se edita aqui; se copia desde `carlostowers/stationvaqueros`.

0021 (BAREBORU 6x6, cuarto juego) aplicada el 2026-11-12: agrega `bareboru6` a los records, tops, borrado del staff y registro anonimo de partidas, con la misma validacion del 3v3 (set a 15). Sin DROP de tablas, DELETE ni TRUNCATE.
Los archivos de `juegos/bareboru6/` son los mismos de STATION (salvo la portada, que lleva el uniforme de Angels): en este dominio usan los colores, el esquema y el top de Angels.
El uno contra uno en linea del 6x6 (juego 0.3.0, app v4.3.0) usa las funciones `bb6_room_create`, `bb6_room_join`, `bb6_room_result` y `bb6_record` del esquema `station` (migracion 0018 de STATION, aplicada el 2026-11-12), con record propio separado del 3v3. En el esquema `angels` no hay tablas de salas.

0022 (cierra las funciones de `public`) aplicada el 2026-11-12 con el permiso de Carlos: quita el permiso de ejecucion de `anon` y `authenticated` en `public.player_bootstrap`, `player_mark_welcomed`, `player_submit_checkin`, `player_submit_overuse` y `make_backup`. No borra funciones, tablas ni datos; el cron `respaldo_semanal` sigue corriendo. Verificado antes: los 461 check-ins y los 11 jugadores de `public` estan en `angels`.
Decision de Carlos (delegada): la copia de datos de salud en `public` se borra el 2026-12-10, 30 dias despues de publicar la v4, con una migracion aparte, verificacion previa y su permiso ese dia.
