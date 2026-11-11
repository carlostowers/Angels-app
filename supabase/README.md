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
